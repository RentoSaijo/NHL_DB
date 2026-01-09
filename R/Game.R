# Load libraries.
suppressMessages(library(tidyverse))
suppressMessages(library(nhlscraper))

# Define helpers.
aggregate_gc_pbps <- function(games) {
  ids <- games %>% pull(id)
  ids %>%
    set_names() %>%
    map(~{nhlscraper::gc_pbp(.x)}) %>%
    bind_rows(.id = 'gameId')
}
aggregate_wsc_pbps <- function(games) {
  ids <- games %>% pull(id)
  ids %>%
    set_names() %>%
    map(~{nhlscraper::wsc_pbp(.x)}) %>%
    bind_rows(.id = 'gameId')
}
aggregate_shifts <- function(games) {
  ids <- games %>% pull(id)
  ids %>%
    set_names() %>%
    map(~{nhlscraper::shifts(.x)}) %>%
    bind_rows(.id = 'gameId')
}

# Get all games.
START_SEASON <- 19171918
END_SEASON   <- 20252026
NHL_GAMES    <- nhlscraper::games() %>% 
  filter(season >= START_SEASON) %>% 
  filter(season <= END_SEASON) %>% 
  filter(gameType %in% 1:3) %>% 
  arrange(id)
write_csv(
  NHL_GAMES, 
  paste0('data/game/meta/NHL_Games_', START_SEASON, '_', END_SEASON, '.csv')
)

# Get all GC play-by-plays.
START_SEASON <- 20052006
END_SEASON   <- 20252026
NHL_GAMES    <- read_csv(
  paste0('data/game/meta/NHL_Games_', 19171918, '_', END_SEASON, '.csv'),
  show_col_types = FALSE
) %>% 
  filter(season >= START_SEASON) %>% 
  filter(season <= END_SEASON) %>% 
  filter(gameStateId == 7)
NHL_SEASONS <- seq(START_SEASON, END_SEASON, by = 10001)
for (s in NHL_SEASONS) {
  games <- NHL_GAMES %>% 
    filter(season == s)
  write_csv(
    aggregate_gc_pbps(games),
    sprintf('data/game/pbps/gc/NHL_PBPS_GC_%s.csv', s)
  )
}

# Get all WSC play-by-plays.
START_SEASON <- 20052006
END_SEASON   <- 20252026
NHL_GAMES    <- read_csv(
  paste0('data/game/meta/NHL_Games_', 19171918, '_', END_SEASON, '.csv'),
  show_col_types = FALSE
) %>% 
  filter(season >= START_SEASON) %>% 
  filter(season <= END_SEASON) %>% 
  filter(gameStateId == 7)
NHL_SEASONS <- seq(START_SEASON, END_SEASON, by = 10001)
for (s in NHL_SEASONS) {
  games <- NHL_GAMES %>% 
    filter(season == s)
  write_csv(
    aggregate_wsc_pbps(games),
    sprintf('data/game/pbps/wsc/NHL_PBPS_WSC_%s.csv', s)
  )
}

# Get all shift charts.
START_SEASON <- 20052006
END_SEASON   <- 20252026
NHL_GAMES    <- read_csv(
  paste0('data/game/meta/NHL_Games_', 19171918, '_', END_SEASON, '.csv'),
  show_col_types = FALSE
) %>% 
  filter(season >= START_SEASON) %>% 
  filter(season <= END_SEASON) %>% 
  filter(gameStateId == 7)
NHL_SEASONS <- seq(START_SEASON, END_SEASON, by = 10001)
for (s in NHL_SEASONS) {
  games <- NHL_GAMES %>% 
    filter(season == s)
  write_csv(
    aggregate_shifts(games),
    sprintf('data/game/shifts/NHL_SHIFTS_%s.csv', s)
  )
}
