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

# Get all games from 1917-1918 to 2024-2025.
NHL_Games_19171918_20242025 <- nhlscraper::games() %>% 
  filter(season <= 20242025) %>% 
  filter(gameType %in% 1:3) %>% 
  arrange(id)
write_csv(
  NHL_Games_19171918_20242025, 
  'data/game/meta/NHL_Games_19171918_20242025.csv'
)

# Get all GC play-by-plays from 2005-2006 to 2024-2025.
NHL_Seasons_20052006_20242025 <- read_csv(
  'data/league/meta/NHL_Seasons_19171918_20242025.csv',
  show_col_types = FALSE
) %>% 
  filter(id >= 20052006)
NHL_Games_20052006_20242025 <- read_csv(
  'data/game/meta/NHL_Games_19171918_20242025.csv',
  show_col_types = FALSE
) %>% 
  filter(season >= 20052006)
for (s in NHL_Seasons_20052006_20242025$id) {
  games <- NHL_Games_20052006_20242025 %>% 
    filter(season == s)
  write_csv(
    aggregate_gc_pbps(games),
    sprintf('data/game/pbps/gc/NHL_PBPS_GC_%s.csv', s)
  )
}

# Get all WSC play-by-plays from 2005-2006 to 2024-2025.
for (s in NHL_Seasons_20052006_20242025$id) {
  games <- NHL_Games_20052006_20242025 %>% 
    filter(season == s)
  write_csv(
    aggregate_wsc_pbps(games), 
    sprintf('data/game/pbps/wsc/NHL_PBPS_WSC_%s.csv', s)
  )
}
