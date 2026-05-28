# ----- Configure Run ----- #

# Read run settings.
args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(name, default = '') {
  prefix <- paste0('--', name, '=')
  hit    <- args[startsWith(args, prefix)]
  if (!length(hit)) {
    env_name     <- toupper(gsub('-', '_', name))
    env_prefixed <- paste0('NHL_DB_', env_name)
    value        <- Sys.getenv(env_prefixed, unset = NA_character_)
    if (is.na(value) || !nzchar(value)) {
      value <- Sys.getenv(env_name, unset = NA_character_)
    }
    if (is.na(value)) {
      return(default)
    }
    return(value)
  }
  sub(prefix, '', hit[[1]], fixed = TRUE)
}
OUTPUT_DIR     <- arg_value('output-dir', 'output')
HF_SOURCE_REPO <- arg_value('hf-source-repo', 'RentoSaijo/NHL_DB')
SEASON_IDS     <- arg_value('seasons', '')
DATASET_IDS    <- arg_value('datasets', '')
UPDATE_DATE    <- arg_value('update-date', '')
MAX_GAMES      <- arg_value('max-games', '')
OFFLINE_SOURCE <- arg_value('offline-source', 'false')
TIMEZONE       <- arg_value('timezone', 'America/New_York')
DOWNLOAD_TIMEOUT <- arg_value('download-timeout', '3600')
DOWNLOAD_RETRIES <- arg_value('download-retries', '3')

# Normalize run settings.
if (!nzchar(UPDATE_DATE)) {
  UPDATE_DATE <- as.character(as.Date(format(Sys.time(), tz = TIMEZONE)))
}
UPDATE_DATE <- as.Date(UPDATE_DATE)
MAX_GAMES   <- suppressWarnings(as.integer(MAX_GAMES))
if (is.na(MAX_GAMES) || MAX_GAMES <= 0L) {
  MAX_GAMES <- Inf
}
OFFLINE_SOURCE <- tolower(OFFLINE_SOURCE) %in% c('true', '1', 'yes', 'y')
DOWNLOAD_TIMEOUT <- suppressWarnings(as.integer(DOWNLOAD_TIMEOUT))
if (is.na(DOWNLOAD_TIMEOUT) || DOWNLOAD_TIMEOUT <= 0L) {
  DOWNLOAD_TIMEOUT <- 3600L
}
DOWNLOAD_RETRIES <- suppressWarnings(as.integer(DOWNLOAD_RETRIES))
if (is.na(DOWNLOAD_RETRIES) || DOWNLOAD_RETRIES <= 0L) {
  DOWNLOAD_RETRIES <- 3L
}
options(timeout = max(getOption('timeout'), DOWNLOAD_TIMEOUT))

# ----- Define Helpers ----- #

# Format elapsed seconds.
format_elapsed_seconds <- function(start_time) {
  sprintf('%.1fs', proc.time()[['elapsed']] - start_time)
}

# Build HuggingFace resolve URL.
hf_url <- function(repo_id, path) {
  paste0(
    'https://huggingface.co/datasets/',
    repo_id,
    '/resolve/main/',
    path
  )
}

# Get remote file status.
get_remote_file_status <- function(url) {
  response <- tryCatch(
    httr2::request(url) |>
      httr2::req_method('HEAD') |>
      httr2::req_timeout(DOWNLOAD_TIMEOUT) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform(),
    error = function(e) e
  )
  if (inherits(response, 'error')) {
    return('unknown')
  }
  status <- httr2::resp_status(response)
  if (status == 404L) {
    return('missing')
  }
  if (status >= 200L && status < 400L) {
    return('exists')
  }
  'unknown'
}

# Download parquet from HuggingFace.
read_hf_parquet <- function(path, repos = c(HF_SOURCE_REPO, 'RentoSaijo/NHL_DB')) {
  local_path <- file.path(OUTPUT_DIR, path)
  if (file.exists(local_path)) {
    return(as.data.frame(arrow::read_parquet(local_path), stringsAsFactors = FALSE))
  }
  if (isTRUE(OFFLINE_SOURCE)) {
    return(NULL)
  }
  for (repo_id in unique(repos[nzchar(repos)])) {
    url    <- hf_url(repo_id, path)
    status <- get_remote_file_status(url)
    if (identical(status, 'missing')) {
      next
    }
    last_error <- NULL
    for (attempt in seq_len(DOWNLOAD_RETRIES)) {
      tmp <- tempfile(fileext = '.parquet')
      ok  <- tryCatch(
        utils::download.file(url, tmp, mode = 'wb', quiet = TRUE) == 0L,
        error = function(e) {
          last_error <<- conditionMessage(e)
          FALSE
        },
        warning = function(w) {
          last_error <<- conditionMessage(w)
          FALSE
        }
      )
      if (isTRUE(ok) && file.exists(tmp) && file.info(tmp)$size > 0L) {
        out <- tryCatch(
          as.data.frame(arrow::read_parquet(tmp), stringsAsFactors = FALSE),
          error = function(e) {
            last_error <<- conditionMessage(e)
            NULL
          }
        )
        if (!is.null(out)) {
          message(sprintf('Loaded existing parquet from %s/%s.', repo_id, path))
          return(out)
        }
      }
      message(sprintf('Attempt %s/%s failed loading %s/%s.', attempt, DOWNLOAD_RETRIES, repo_id, path))
    }
    if (!is.null(last_error) && grepl('404|Not Found', last_error, ignore.case = TRUE)) {
      next
    }
    stop(sprintf(
      'Unable to load existing parquet from %s/%s; aborting to avoid treating remote data as missing. Last error: %s',
      repo_id,
      path,
      ifelse(is.null(last_error), 'unknown', last_error)
    ))
  }
  NULL
}

# Write parquet to output directory.
write_output_parquet <- function(data, path) {
  file_path <- file.path(OUTPUT_DIR, path)
  dir.create(dirname(file_path), recursive = TRUE, showWarnings = FALSE)
  arrow::write_parquet(data, file_path)
  message(sprintf('Wrote %s row(s) to %s.', nrow(data), file_path))
  invisible(file_path)
}

# Bucket column type.
get_column_type_bucket <- function(x) {
  if (inherits(x, 'POSIXct')) {
    return('datetime')
  }
  if (inherits(x, 'Date')) {
    return('date')
  }
  if (is.factor(x) || is.character(x)) {
    return('character')
  }
  if (is.integer(x)) {
    return('integer')
  }
  if (is.double(x)) {
    return('double')
  }
  if (is.logical(x)) {
    return('logical')
  }
  if (is.list(x)) {
    return('list')
  }
  class(x)[[1]]
}

# Create typed missing vector.
get_typed_na_vector <- function(target_type, n) {
  switch(
    target_type,
    character = rep(NA_character_, n),
    double    = rep(NA_real_, n),
    integer   = rep(NA_integer_, n),
    logical   = rep(NA, n),
    date      = as.Date(rep(NA_character_, n)),
    datetime  = as.POSIXct(rep(NA_character_, n), tz = 'UTC'),
    list      = vector('list', n),
    rep(NA_character_, n)
  )
}

# Choose common column type.
choose_common_column_type <- function(column_vectors) {
  non_missing_vectors <- Filter(function(x) length(x) > 0L && !all(is.na(x)), column_vectors)
  non_missing_types   <- unique(vapply(non_missing_vectors, get_column_type_bucket, character(1)))
  if (!length(non_missing_types)) {
    all_types <- unique(vapply(column_vectors, get_column_type_bucket, character(1)))
    if (all(all_types %in% c('double', 'integer', 'logical'))) {
      return('double')
    }
    if (length(all_types) == 1L) {
      return(all_types[[1]])
    }
    return('character')
  }
  if (all(non_missing_types %in% c('double', 'integer', 'logical'))) {
    if (identical(non_missing_types, 'logical')) {
      return('logical')
    }
    if ('double' %in% non_missing_types || 'logical' %in% non_missing_types) {
      return('double')
    }
    return('integer')
  }
  if (length(non_missing_types) == 1L) {
    return(non_missing_types[[1]])
  }
  'character'
}

# Coerce column to type.
coerce_column_to_type <- function(x, target_type) {
  if (all(is.na(x))) {
    return(get_typed_na_vector(target_type, length(x)))
  }
  switch(
    target_type,
    character = as.character(x),
    double    = as.double(x),
    integer   = as.integer(x),
    logical   = as.logical(x),
    date      = as.Date(x),
    datetime  = as.POSIXct(x, tz = 'UTC'),
    list      = as.list(x),
    as.character(x)
  )
}

# Normalize result column types.
normalize_result_column_types <- function(results, progress_label) {
  results <- lapply(results, function(x) {
    if (is.null(x)) {
      return(data.frame())
    }
    as.data.frame(x, stringsAsFactors = FALSE)
  })
  all_columns <- unique(unlist(lapply(results, names), use.names = FALSE))
  if (!length(all_columns)) {
    return(results)
  }
  mixed_columns  <- character()
  sparse_columns <- character()
  target_types   <- setNames(vector('list', length(all_columns)), all_columns)
  for (column_name in all_columns) {
    column_vectors  <- lapply(results, function(x) if (column_name %in% names(x)) x[[column_name]] else NULL)
    present_vectors <- Filter(Negate(is.null), column_vectors)
    if (!length(present_vectors)) {
      next
    }
    source_types <- unique(vapply(present_vectors, get_column_type_bucket, character(1)))
    target_type  <- choose_common_column_type(present_vectors)
    target_types[[column_name]] <- target_type
    if (length(source_types) > 1L) {
      mixed_columns <- c(mixed_columns, column_name)
    }
    if (any(vapply(column_vectors, is.null, logical(1)))) {
      sparse_columns <- c(sparse_columns, column_name)
    }
  }
  results <- lapply(results, function(x) {
    for (column_name in all_columns) {
      target_type <- target_types[[column_name]]
      if (is.null(target_type)) {
        next
      }
      if (!column_name %in% names(x)) {
        x[[column_name]] <- get_typed_na_vector(target_type, nrow(x))
      } else {
        x[[column_name]] <- coerce_column_to_type(x[[column_name]], target_type)
      }
    }
    x[all_columns]
  })
  if (length(mixed_columns)) {
    message(sprintf(
      '%s: normalized mixed-type columns before binding: %s',
      progress_label,
      paste(sort(unique(mixed_columns)), collapse = ', ')
    ))
  }
  if (length(sparse_columns)) {
    message(sprintf(
      '%s: filled missing columns before binding: %s',
      progress_label,
      paste(sort(unique(sparse_columns)), collapse = ', ')
    ))
  }
  results
}

# Sort game rows.
sort_game_rows <- function(game_data) {
  if (is.null(game_data) || !nrow(game_data)) {
    return(game_data)
  }
  sort_columns <- c(
    'gameId',
    'sortOrder',
    'eventId',
    'teamId',
    'playerId',
    'shiftNumber',
    'period',
    'periodNumber',
    'startSecondsElapsedInGame',
    'startSecondsElapsedInPeriod'
  )
  sort_columns <- intersect(sort_columns, names(game_data))
  if (!length(sort_columns)) {
    return(game_data)
  }
  game_data[do.call(order, game_data[sort_columns]), , drop = FALSE]
}

# Get scraped game IDs.
get_scraped_game_ids <- function(existing_data) {
  if (is.null(existing_data) || !nrow(existing_data) || !'gameId' %in% names(existing_data)) {
    return(character())
  }
  unique(as.character(existing_data$gameId))
}

# Aggregate game data.
aggregate_game_data <- function(games, fetch_fun, progress_label, progress_every = 100L) {
  game_ids <- games$gameId
  results  <- vector('list', length(game_ids))
  for (i in seq_along(game_ids)) {
    game_id <- game_ids[[i]]
    results[[i]] <- tryCatch(
      {
        out <- as.data.frame(fetch_fun(game_id), stringsAsFactors = FALSE)
        if (nrow(out) && !'gameId' %in% names(out)) {
          out$gameId <- as.integer(game_id)
        }
        out
      },
      error = function(e) {
        message(sprintf('%s: failed game %s: %s', progress_label, game_id, conditionMessage(e)))
        data.frame()
      }
    )
    if (i %% progress_every == 0L || i == length(game_ids)) {
      message(sprintf('%s: %s/%s games complete.', progress_label, i, length(game_ids)))
    }
  }
  results <- normalize_result_column_types(results, progress_label)
  if (!length(results)) {
    return(data.frame())
  }
  do.call(rbind, results)
}

# Merge game data.
merge_game_data <- function(existing_data, new_data, progress_label) {
  results <- Filter(Negate(is.null), list(existing_data, new_data))
  if (!length(results)) {
    return(data.frame())
  }
  results <- normalize_result_column_types(results, sprintf('%s merge', progress_label))
  sort_game_rows(do.call(rbind, results))
}

# Update season parquet.
update_season_parquet <- function(games, path, fetch_fun, progress_label) {
  existing_data    <- read_hf_parquet(path)
  scraped_game_ids <- get_scraped_game_ids(existing_data)
  games_to_scrape  <- games[!as.character(games$gameId) %in% scraped_game_ids, , drop = FALSE]
  if (is.finite(MAX_GAMES)) {
    games_to_scrape <- head(games_to_scrape, MAX_GAMES)
  }
  message(sprintf(
    '%s: %s existing games found, %s games remaining to scrape.',
    progress_label,
    length(scraped_game_ids),
    nrow(games_to_scrape)
  ))
  if (!nrow(games_to_scrape)) {
    message(sprintf('%s: no new games found; leaving remote parquet unchanged.', progress_label))
    return(invisible(existing_data))
  }
  new_data    <- aggregate_game_data(games_to_scrape, fetch_fun, progress_label = progress_label)
  if (!nrow(new_data)) {
    message(sprintf('%s: no new rows were returned; leaving remote parquet unchanged.', progress_label))
    return(invisible(existing_data))
  }
  merged_data <- merge_game_data(existing_data, new_data, progress_label)
  write_output_parquet(merged_data, path)
  invisible(merged_data)
}

# Parse season date.
season_date <- function(x) {
  as.Date(substr(as.character(x), 1L, 10L))
}

# Get seasons to update.
get_update_seasons <- function(update_date, season_ids = SEASON_IDS) {
  if (nzchar(season_ids)) {
    return(as.integer(strsplit(season_ids, ',', fixed = TRUE)[[1]]))
  }
  seasons <- nhlscraper::seasons()
  start   <- season_date(ifelse(is.na(seasons$preseasonStartdate), seasons$startDate, seasons$preseasonStartdate))
  end     <- season_date(seasons$endDate)
  seasons$seasonId[start <= update_date & end >= update_date]
}

# Get completed games.
get_completed_games <- function(season_ids, update_date) {
  games <- nhlscraper::games()
  games$gameDate <- as.Date(games$gameDate)
  games <- games[
    games$seasonId %in% season_ids &
      games$gameTypeId %in% 1:3 &
      games$gameStateId == 7L &
      games$gameDate < update_date,
    ,
    drop = FALSE
  ]
  games[order(games$gameId), , drop = FALSE]
}

# ----- Update Game Datasets ----- #

# Define datasets.
datasets <- list(
  list(
    id       = 'gc_raw',
    label    = 'GC raw play-by-play',
    path     = 'data/game/pbps/gc/NHL_PBPS_GC_Raw_%s.parquet',
    fetch_fun = nhlscraper::gc_play_by_play_raw
  ),
  list(
    id       = 'gc',
    label    = 'GC play-by-play',
    path     = 'data/game/pbps/gc/NHL_PBPS_GC_%s.parquet',
    fetch_fun = nhlscraper::gc_play_by_play
  ),
  list(
    id       = 'wsc_raw',
    label    = 'WSC raw play-by-play',
    path     = 'data/game/pbps/wsc/NHL_PBPS_WSC_Raw_%s.parquet',
    fetch_fun = nhlscraper::wsc_play_by_play_raw
  ),
  list(
    id       = 'wsc',
    label    = 'WSC play-by-play',
    path     = 'data/game/pbps/wsc/NHL_PBPS_WSC_%s.parquet',
    fetch_fun = nhlscraper::wsc_play_by_play
  ),
  list(
    id       = 'scs',
    label    = 'Shift charts',
    path     = 'data/game/scs/NHL_SCS_%s.parquet',
    fetch_fun = nhlscraper::shift_chart
  ),
  list(
    id       = 'scss',
    label    = 'Shift chart summaries',
    path     = 'data/game/scss/NHL_SCSS_%s.parquet',
    fetch_fun = nhlscraper::shift_chart_summary
  )
)

# Filter datasets.
if (nzchar(DATASET_IDS)) {
  requested_dataset_ids <- trimws(strsplit(DATASET_IDS, ',', fixed = TRUE)[[1]])
  supported_dataset_ids <- vapply(datasets, `[[`, character(1), 'id')
  invalid_dataset_ids   <- setdiff(requested_dataset_ids, supported_dataset_ids)
  if (length(invalid_dataset_ids)) {
    stop(sprintf(
      'Unsupported dataset(s): %s. Supported datasets: %s.',
      paste(invalid_dataset_ids, collapse = ', '),
      paste(supported_dataset_ids, collapse = ', ')
    ))
  }
  datasets <- datasets[supported_dataset_ids %in% requested_dataset_ids]
}

# Update datasets.
season_ids <- get_update_seasons(UPDATE_DATE)
games      <- get_completed_games(season_ids, UPDATE_DATE)
message(sprintf(
  'Updating game datasets for %s completed game(s) across season(s): %s.',
  nrow(games),
  paste(season_ids, collapse = ', ')
))
for (season_id in season_ids) {
  season_games <- games[games$seasonId == season_id, , drop = FALSE]
  for (dataset in datasets) {
    start_time <- proc.time()[['elapsed']]
    path       <- sprintf(dataset$path, season_id)
    label      <- sprintf('%s %s', dataset$label, season_id)
    message(sprintf('Fetching %s (%s games).', label, nrow(season_games)))
    update_season_parquet(
      games          = season_games,
      path           = path,
      fetch_fun      = dataset$fetch_fun,
      progress_label = label
    )
    message(sprintf('Finished %s in %s.', label, format_elapsed_seconds(start_time)))
  }
}
