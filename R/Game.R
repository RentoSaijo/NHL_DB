# Load libraries.
suppressMessages(library(tidyverse))
suppressMessages(library(nhlscraper))

# Define helpers.
get_gc_pbps <- function(games) {
  ids <- games %>% pull(id)
  ids %>%
    set_names() %>%
    map(~{
      pbp <- get_gc_play_by_play(.x)
      if (is.null(pbp) || nrow(pbp) == 0) {
        tibble()
      } else {
        as_tibble(pbp)
      }
    }) %>%
    bind_rows(.id = 'gameId')
}

get_wsc_pbps <- function(games) {
  ids <- games %>% pull(id)
  ids %>%
    set_names() %>%
    map(~{
      pbp <- get_wsc_play_by_play(.x)
      if (is.null(pbp) || nrow(pbp) == 0) {
        tibble()
      } else {
        as_tibble(pbp)
      }
    }) %>%
    bind_rows(.id = 'gameId')
}

# Get all games from 1917-1918 to 2024-2025.
NHL_Games_19171918_20242025 <- get_games() %>% 
  filter(season <= 20242025) %>% 
  arrange(season, gameNumber)
write_csv(
  NHL_Games_19171918_20242025, 
  'data/game/meta/NHL_Games_19171918_20242025.csv'
)

# Get all GC play-by-plays from 2005-2006 to 2024-2025.
NHL_Seasons_20052006_20242025 <- read_csv(
  'data/league/meta/NHL_Seasons_19171918_20242025.csv',
  show_col_types=FALSE
) %>% 
  filter(id >= 20052006)
NHL_Games_20052006_20242025 <- read_csv(
  'data/game/meta/NHL_Games_19171918_20242025.csv'
) %>% 
  filter(season >= 20052006)
for (s in NHL_Seasons_20052006_20242025$id) {
  games <- NHL_Games_20052006_20242025 %>% 
    filter(season == s)
  write_csv(
    get_gc_pbps(games),
    sprintf('data/game/pbps/gc/NHL_PBPS_GC_%s.csv', s)
  )
}

# Get all WSC play-by-plays from 2005-2006 to 2024-2025.
NHL_Seasons_20052006_20242025 <- read_csv(
  'data/league/meta/NHL_Seasons_19171918_20242025.csv',
  show_col_types=FALSE
) %>% 
  filter(id >= 20052006)
NHL_Games_20052006_20242025 <- read_csv(
  'data/game/meta/NHL_Games_19171918_20242025.csv'
) %>% 
  filter(season >= 20052006)
for (s in NHL_Seasons_20052006_20242025$id) {
  games <- NHL_Games_20052006_20242025 %>% 
    filter(season == s)
  write_csv(
    get_wsc_pbps(games), 
    sprintf('data/game/pbps/wsc/NHL_PBPS_WSC_%s.csv', s)
  )
}
