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
UPDATE_DATE    <- arg_value('update-date', '')
MAX_EVENTS     <- arg_value('max-events', '')
OFFLINE_SOURCE <- arg_value('offline-source', 'false')
TIMEZONE       <- arg_value('timezone', 'America/New_York')
DOWNLOAD_TIMEOUT <- arg_value('download-timeout', '3600')
DOWNLOAD_RETRIES <- arg_value('download-retries', '3')

# Normalize run settings.
if (!nzchar(UPDATE_DATE)) {
  UPDATE_DATE <- as.character(as.Date(format(Sys.time(), tz = TIMEZONE)))
}
UPDATE_DATE <- as.Date(UPDATE_DATE)
MAX_EVENTS  <- suppressWarnings(as.integer(MAX_EVENTS))
if (is.na(MAX_EVENTS) || MAX_EVENTS <= 0L) {
  MAX_EVENTS <- Inf
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

# Sort replay rows.
sort_replay_rows <- function(replays) {
  if (is.null(replays) || !nrow(replays)) {
    return(replays)
  }
  sort_columns <- intersect(c('gameId', 'eventId', 'timeInSeconds', 'timeInDeciseconds'), names(replays))
  if (!length(sort_columns)) {
    return(replays)
  }
  replays[do.call(order, replays[sort_columns]), , drop = FALSE]
}

# Bind replay rows with dynamic columns.
bind_dynamic_rows <- function(rows) {
  rows <- Filter(function(x) is.data.frame(x) && nrow(x), rows)
  if (!length(rows)) {
    return(data.frame())
  }
  columns <- unique(unlist(lapply(rows, names), use.names = FALSE))
  rows <- lapply(rows, function(x) {
    missing_columns <- setdiff(columns, names(x))
    for (column in missing_columns) {
      x[[column]] <- NA
    }
    x[, columns, drop = FALSE]
  })
  do.call(rbind, rows)
}

# Create empty replay index.
empty_replay_index <- function() {
  data.frame(
    gameId          = integer(),
    eventId         = integer(),
    status          = character(),
    rowCount        = integer(),
    lastAttemptedAt = character(),
    stringsAsFactors = FALSE
  )
}

# Normalize replay index.
normalize_replay_index <- function(index) {
  if (is.null(index) || !nrow(index)) {
    return(empty_replay_index())
  }
  for (column in names(empty_replay_index())) {
    if (!column %in% names(index)) {
      index[[column]] <- NA
    }
  }
  index <- index[, names(empty_replay_index()), drop = FALSE]
  index$gameId          <- as.integer(index$gameId)
  index$eventId         <- as.integer(index$eventId)
  index$status          <- as.character(index$status)
  index$rowCount        <- as.integer(index$rowCount)
  index$lastAttemptedAt <- as.character(index$lastAttemptedAt)
  index$key <- paste(index$gameId, index$eventId, sep = '-')
  index <- index[!duplicated(index$key, fromLast = TRUE), names(empty_replay_index()), drop = FALSE]
  index[order(index$gameId, index$eventId), , drop = FALSE]
}

# Build replay index from replay rows.
build_replay_index_from_replays <- function(replays) {
  if (is.null(replays) || !nrow(replays) || !all(c('gameId', 'eventId') %in% names(replays))) {
    return(empty_replay_index())
  }
  counts <- stats::aggregate(
    x  = list(rowCount = rep(1L, nrow(replays))),
    by = list(gameId = as.integer(replays$gameId), eventId = as.integer(replays$eventId)),
    FUN = sum
  )
  counts$status          <- 'success'
  counts$lastAttemptedAt <- NA_character_
  normalize_replay_index(counts)
}

# Merge replay index rows.
merge_replay_index <- function(existing_index, new_index) {
  existing_index <- normalize_replay_index(existing_index)
  new_index      <- normalize_replay_index(new_index)
  if (!nrow(new_index)) {
    return(existing_index)
  }
  existing_index$key <- paste(existing_index$gameId, existing_index$eventId, sep = '-')
  new_index$key      <- paste(new_index$gameId, new_index$eventId, sep = '-')
  existing_index     <- existing_index[!existing_index$key %in% new_index$key, names(empty_replay_index()), drop = FALSE]
  normalize_replay_index(rbind(existing_index, new_index[, names(empty_replay_index()), drop = FALSE]))
}

# Get replay index skip keys.
get_replay_index_skip_keys <- function(index) {
  index <- normalize_replay_index(index)
  index <- index[index$status %in% c('success', 'empty'), , drop = FALSE]
  unique(paste(index$gameId, index$eventId, sep = '-'))
}

# Get goal events.
get_goal_events <- function(pbps, season_id) {
  event_type_column <- intersect(c('eventTypeDescKey', 'typeDescKey'), names(pbps))
  if (!length(event_type_column)) {
    message(sprintf('GC play-by-play parquet for %s lacks goal-event columns; skipping replays.', season_id))
    return(NULL)
  }
  event_type_column <- event_type_column[[1]]
  unique(pbps[pbps[[event_type_column]] == 'goal', c('gameId', 'eventId'), drop = FALSE])
}

# Aggregate replays.
aggregate_replays <- function(events, progress_label = 'Replays', progress_every = 100L) {
  if (!nrow(events)) {
    return(list(replays = data.frame(), index = empty_replay_index()))
  }
  results <- vector('list', nrow(events))
  attempts <- vector('list', nrow(events))
  success_count <- 0L
  empty_count  <- 0L
  failed_count <- 0L
  for (i in seq_len(nrow(events))) {
    game_id  <- events$gameId[[i]]
    event_id <- events$eventId[[i]]
    status   <- 'error'
    row_count <- 0L
    attempted_at <- format(Sys.time(), '%Y-%m-%dT%H:%M:%SZ', tz = 'UTC')
    results[[i]] <- tryCatch(
      {
        replay_df <- as.data.frame(nhlscraper::replay(game_id, event_id), stringsAsFactors = FALSE)
        row_count <- nrow(replay_df)
        if (!row_count) {
          status <- 'empty'
          data.frame()
        } else {
          status <- 'success'
          replay_df$gameId  <- as.integer(game_id)
          replay_df$eventId <- as.integer(event_id)
          replay_df[, c('gameId', 'eventId', setdiff(names(replay_df), c('gameId', 'eventId'))), drop = FALSE]
        }
      },
      error = function(e) {
        message(sprintf('%s: failed game %s event %s: %s', progress_label, game_id, event_id, conditionMessage(e)))
        data.frame()
      }
    )
    attempts[[i]] <- data.frame(
      gameId          = as.integer(game_id),
      eventId         = as.integer(event_id),
      status          = status,
      rowCount        = as.integer(row_count),
      lastAttemptedAt = attempted_at,
      stringsAsFactors = FALSE
    )
    success_count <- success_count + as.integer(status == 'success')
    empty_count   <- empty_count + as.integer(status == 'empty')
    failed_count  <- failed_count + as.integer(status == 'error')
    if (i %% progress_every == 0L || i == nrow(events)) {
      message(sprintf(
        '%s: %s/%s events complete (%s success, %s empty, %s failed).',
        progress_label,
        i,
        nrow(events),
        success_count,
        empty_count,
        failed_count
      ))
    }
  }
  list(
    replays = bind_dynamic_rows(results),
    index   = normalize_replay_index(do.call(rbind, attempts))
  )
}

# Update season replay parquet.
update_season_replays <- function(season_id) {
  pbp_path    <- sprintf('data/game/pbps/gc/NHL_PBPS_GC_%s.parquet', season_id)
  replay_path <- sprintf('data/event/replays/NHL_REPLAYS_%s.parquet', season_id)
  index_path  <- sprintf('data/event/replays/index/NHL_REPLAYS_INDEX_%s.parquet', season_id)
  pbps        <- read_hf_parquet(pbp_path)
  if (is.null(pbps) || !nrow(pbps)) {
    message(sprintf('No GC play-by-play parquet found for %s; skipping replays.', season_id))
    return(invisible(NULL))
  }
  if (!all(c('gameId', 'eventId') %in% names(pbps))) {
    message(sprintf('GC play-by-play parquet for %s lacks event identity columns; skipping replays.', season_id))
    return(invisible(NULL))
  }
  existing_replays <- NULL
  replay_index     <- read_hf_parquet(index_path)
  if (is.null(replay_index)) {
    existing_replays <- read_hf_parquet(replay_path)
    replay_index     <- build_replay_index_from_replays(existing_replays)
    if (nrow(replay_index)) {
      write_output_parquet(replay_index, index_path)
      message(sprintf('Seeded replay index for %s from existing replay parquet.', season_id))
    }
  } else {
    replay_index <- normalize_replay_index(replay_index)
  }
  existing_keys <- get_replay_index_skip_keys(replay_index)
  events <- get_goal_events(pbps, season_id)
  if (is.null(events)) {
    return(invisible(NULL))
  }
  events$key <- paste(events$gameId, events$eventId, sep = '-')
  events     <- events[!events$key %in% existing_keys, c('gameId', 'eventId'), drop = FALSE]
  if (is.finite(MAX_EVENTS)) {
    events <- head(events, MAX_EVENTS)
  }
  message(sprintf(
    'Replays %s: %s existing goal events found, %s events remaining to scrape.',
    season_id,
    length(existing_keys),
    nrow(events)
  ))
  if (!nrow(events)) {
    message(sprintf('Replays %s: no new goal events found; leaving remote parquet unchanged.', season_id))
    return(invisible(replay_index))
  }
  replay_update <- aggregate_replays(events, progress_label = sprintf('Replays %s', season_id))
  replay_index  <- merge_replay_index(replay_index, replay_update$index)
  write_output_parquet(replay_index, index_path)
  if (!nrow(replay_update$replays)) {
    message(sprintf('Replays %s: no new replay rows were returned; leaving remote parquet unchanged.', season_id))
    return(invisible(replay_index))
  }
  if (is.null(existing_replays)) {
    existing_replays <- read_hf_parquet(replay_path)
  }
  merged      <- bind_dynamic_rows(list(existing_replays, replay_update$replays))
  merged      <- sort_replay_rows(merged)
  write_output_parquet(merged, replay_path)
  invisible(merged)
}

# ----- Update Event Datasets ----- #

# Update replay datasets.
season_ids <- get_update_seasons(UPDATE_DATE)
message(sprintf('Updating event datasets for season(s): %s.', paste(season_ids, collapse = ', ')))
for (season_id in season_ids) {
  start_time <- proc.time()[['elapsed']]
  update_season_replays(season_id)
  message(sprintf('Finished replays %s in %s.', season_id, format_elapsed_seconds(start_time)))
}
