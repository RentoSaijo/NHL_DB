# Load libraries.
suppressMessages(library(tidyverse))
suppressMessages(library(nhlscraper))

# Get all players registered by 09-16-2025.
NHL_Players_09_16_2025 <- get_players() %>% 
  arrange(id)
write_csv(
  NHL_Players_09_16_2025, 
  'data/player/meta/NHL_Players_09_16_2025.csv'
)
