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
HF_SOURCE_REPO <- arg_value('hf-source-repo', 'RentoSaijo/NHL_DB-staging')
SEASON_IDS     <- arg_value('seasons', '')
UPDATE_DATE    <- arg_value('update-date', '')
MAX_EVENTS     <- arg_value('max-events', '')
OFFLINE_SOURCE <- arg_value('offline-source', 'false')
TIMEZONE       <- arg_value('timezone', 'America/New_York')

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
    tmp <- tempfile(fileext = '.parquet')
    ok  <- tryCatch(
      utils::download.file(hf_url(repo_id, path), tmp, mode = 'wb', quiet = TRUE) == 0L,
      error = function(e) FALSE,
      warning = function(w) FALSE
    )
    if (isTRUE(ok) && file.exists(tmp) && file.info(tmp)$size > 0L) {
      message(sprintf('Loaded existing parquet from %s/%s.', repo_id, path))
      return(as.data.frame(arrow::read_parquet(tmp), stringsAsFactors = FALSE))
    }
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

# Get existing replay keys.
get_existing_replay_keys <- function(replays) {
  if (is.null(replays) || !nrow(replays) || !all(c('gameId', 'eventId') %in% names(replays))) {
    return(character())
  }
  unique(paste(replays$gameId, replays$eventId, sep = '-'))
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
    return(data.frame(gameId = integer(), eventId = integer()))
  }
  results <- vector('list', nrow(events))
  empty_count  <- 0L
  failed_count <- 0L
  for (i in seq_len(nrow(events))) {
    game_id  <- events$gameId[[i]]
    event_id <- events$eventId[[i]]
    results[[i]] <- tryCatch(
      {
        replay_df <- as.data.frame(nhlscraper::replay(game_id, event_id), stringsAsFactors = FALSE)
        if (!nrow(replay_df)) {
          empty_count <<- empty_count + 1L
          data.frame()
        } else {
          replay_df$gameId  <- as.integer(game_id)
          replay_df$eventId <- as.integer(event_id)
          replay_df[, c('gameId', 'eventId', setdiff(names(replay_df), c('gameId', 'eventId'))), drop = FALSE]
        }
      },
      error = function(e) {
        failed_count <<- failed_count + 1L
        message(sprintf('%s: failed game %s event %s: %s', progress_label, game_id, event_id, conditionMessage(e)))
        data.frame()
      }
    )
    if (i %% progress_every == 0L || i == nrow(events)) {
      replay_count <- sum(vapply(results[seq_len(i)], function(x) is.data.frame(x) && nrow(x), logical(1)))
      message(sprintf(
        '%s: %s/%s events complete (%s replay event(s), %s empty, %s failed).',
        progress_label,
        i,
        nrow(events),
        replay_count,
        empty_count,
        failed_count
      ))
    }
  }
  bind_dynamic_rows(results)
}

# Update season replay parquet.
update_season_replays <- function(season_id) {
  pbp_path    <- sprintf('data/game/pbps/gc/NHL_PBPS_GC_%s.parquet', season_id)
  replay_path <- sprintf('data/event/replays/NHL_REPLAYS_%s.parquet', season_id)
  pbps        <- read_hf_parquet(pbp_path)
  if (is.null(pbps) || !nrow(pbps)) {
    message(sprintf('No GC play-by-play parquet found for %s; skipping replays.', season_id))
    return(invisible(NULL))
  }
  if (!all(c('gameId', 'eventId') %in% names(pbps))) {
    message(sprintf('GC play-by-play parquet for %s lacks event identity columns; skipping replays.', season_id))
    return(invisible(NULL))
  }
  existing_replays <- read_hf_parquet(replay_path)
  existing_keys    <- get_existing_replay_keys(existing_replays)
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
    return(invisible(existing_replays))
  }
  new_replays <- aggregate_replays(events, progress_label = sprintf('Replays %s', season_id))
  if (!nrow(new_replays)) {
    message(sprintf('Replays %s: no new replay rows were returned; leaving remote parquet unchanged.', season_id))
    return(invisible(existing_replays))
  }
  merged      <- bind_dynamic_rows(list(existing_replays, new_replays))
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
