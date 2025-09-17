# Load libraries.
suppressMessages(library(tidyverse))
suppressMessages(library(nhlscraper))

# Get all seasons from 1917-1918 to 2024-2025.
NHL_Seasons_19171918_20242025 <- get_seasons() %>% 
  filter(id <= 20242025) %>% 
  arrange(id)
NHL_Standings_Information_19171918_20242025 <- get_standings_information() %>%
  select(-pointForOTlossInUse) %>% 
  filter(id <= 20242025) %>% 
  arrange(id)
NHL_Seasons_19171918_20242025 <- left_join(
  NHL_Seasons_19171918_20242025, 
  NHL_Standings_Information_19171918_20242025,
  by = 'id',
  suffix = c('', '.y')
  ) %>% 
    select(-ends_with('.y'))
write_csv(
  NHL_Seasons_19171918_20242025, 
  'data/meta/NHL_Seasons_19171918_20242025.csv'
)

# Get all teams from 1917-1918 to 2024-2025.
NHL_Teams_19171918_20242025 <- get_teams() %>% 
  filter(!id %in% c(70, 99, 68)) %>% 
  arrange(id)
write_csv(
  NHL_Teams_19171918_20242025, 
  'data/meta/NHL_Teams_19171918_20242025.csv'
)

# Get all franchises from 1917-1918 to 2024-2025.
NHL_Franchises_19171918_20242025 <- get_franchises() %>% 
  arrange(id)
write_csv(
  NHL_Franchises_19171918_20242025, 
  'data/meta/NHL_Franchises_19171918_20242025.csv'
)

# Get all players registered by 09-16-2025.
NHL_Players_09_16_2025 <- get_players() %>% 
  arrange(id)
write_csv(
  NHL_Players_09_16_2025, 
  'data/meta/NHL_Players_09_16_2025.csv'
)

# Get all games from 1917-1918 to 2024-2025.
NHL_Games_19171918_20242025 <- get_games() %>% 
  filter(season <= 20242025) %>% 
  arrange(season, gameNumber)
write_csv(
  NHL_Games_19171918_20242025, 
  'data/meta/NHL_Games_19171918_20242025.csv'
)

