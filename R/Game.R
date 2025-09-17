# Load libraries.
suppressMessages(library(tidyverse))
suppressMessages(library(nhlscraper))

# Get all games from 1917-1918 to 2024-2025.
NHL_Games_19171918_20242025 <- get_games() %>% 
  filter(season <= 20242025) %>% 
  arrange(season, gameNumber)
write_csv(
  NHL_Games_19171918_20242025, 
  'data/game/meta/NHL_Games_19171918_20242025.csv'
)
