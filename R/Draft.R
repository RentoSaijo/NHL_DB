# Load libraries.
suppressMessages(library(tidyverse))
suppressMessages(library(nhlscraper))

# Get all drafts from 1917-1918 to 20242025.
NHL_Drafts_19171918_20242025 <- get_drafts() %>% 
  filter(draftYear <= 20242025%%10000)
write_csv(
  NHL_Drafts_19171918_20242025, 
  'data/draft/meta/NHL_Drafts_19171918_20242025.csv'
)

# Get all draft picks from 1917-1918 to 20242025.
NHL_Draft_Picks_19171918_20242025 <- get_draft_picks() %>% 
  filter(draftYear <= 20242025%%10000) %>% 
  arrange(draftYear, supplementalDraft, overallPickNumber)
write_csv(
  NHL_Drafts_19171918_20242025, 
  'data/draft/NHL_Draft_Picks_19171918_20242025.csv'
)
