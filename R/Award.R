# Load libraries.
suppressMessages(library(tidyverse))
suppressMessages(library(nhlscraper))

# Get all awards from 1917-1918 to 20242025.
NHL_Awards_19171918_20242025 <- get_awards() %>% 
  arrange(id)
write_csv(
  NHL_Awards_19171918_20242025, 
  'data/award/meta/NHL_Awards_19171918_20242025.csv'
)

# Get all award winners from 1917-1918 to 20242025.
NHL_Award_Winners_19171918_20242025 <- get_award_winners() %>% 
  filter(seasonId <= 20242025) %>% 
  arrange(seasonId, trophyId, desc(status))
write_csv(
  NHL_Award_Winners_19171918_20242025, 
  'data/award/NHL_Award_Winners_19171918_20242025.csv'
)
