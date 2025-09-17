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
  'data/league/meta/NHL_Seasons_19171918_20242025.csv'
)
