# Load libraries.
suppressMessages(library(tidyverse))
suppressMessages(library(nhlscraper))

# Get terminologies registered by 09-16-2025.
NHL_Glossary_09_16_2025 <- get_glossary() %>% 
  arrange(id)
write_csv(
  NHL_Glossary_09_16_2025, 
  'data/other/NHL_Glossary_09_16_2025.csv'
)

# Get countries registered by 09-16-2025.
NHL_Countries_09_16_2025 <- get_countries() %>% 
  arrange(id)
write_csv(
  NHL_Countries_09_16_2025, 
  'data/other/NHL_Countries_09_16_2025.csv'
)

# Get venues registered by 09-16-2025.
NHL_Venues_09_16_2025 <- get_venues() %>% 
  arrange(venueId)
write_csv(
  NHL_Venues_09_16_2025, 
  'data/other/NHL_Venues_09_16_2025.csv'
)

# Get attendances from 1917-1918 to 2024-2025.
NHL_Attendances_19171918_20242025 <- get_attendance() %>% 
  arrange(seasonId)
write_csv(
  NHL_Attendances_19171918_20242025, 
  'data/other/NHL_Attendances_19171918_20242025.csv'
)
