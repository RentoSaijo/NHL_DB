# Load libraries.
suppressMessages(library(tidyverse))
suppressMessages(library(nhlscraper))

# Get all teams from 1917-1918 to 2025-2026.
NHL_Teams_19171918_20252026 <- get_teams() %>% 
  filter(!id %in% c(70, 99)) %>% 
  arrange(id)
write_csv(
  NHL_Teams_19171918_20252026, 
  'data/team/meta/NHL_Teams_19171918_20252026.csv'
)

# Get all franchises from 1917-1918 to 2024-2025.
NHL_Franchises_19171918_20242025 <- get_franchises() %>% 
  arrange(id)
write_csv(
  NHL_Franchises_19171918_20242025, 
  'data/team/meta/NHL_Franchises_19171918_20242025.csv'
)

# Get all franchises' seasons from 1917-1918 to 2024-2025.
NHL_Franchise_Seasons_19171918_20242025 <- get_franchise_season_by_season() %>%
  filter(seasonId <= 20242025) %>% 
  arrange(franchiseId, seasonId)
write_csv(
  NHL_Franchise_Seasons_19171918_20242025, 
  'data/team/NHL_Franchise_Seasons_19171918_20242025.csv'
)
