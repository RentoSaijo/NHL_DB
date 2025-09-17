# Get all franchises' seasons from 1917-1918 to 2024-2025.
NHL_Franchise_Seasons_19171918_20242025 <- get_franchise_season_by_season() %>%
  filter(seasonId <= 20242025) %>% 
  arrange(franchiseId, seasonId)
write_csv(
  NHL_Franchise_Seasons_19171918_20242025, 
  'data/team/NHL_Franchise_Seasons_19171918_20242025.csv'
)
