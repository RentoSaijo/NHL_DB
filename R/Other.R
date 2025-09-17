# Load libraries.
suppressMessages(library(tidyverse))
suppressMessages(library(nhlscraper))

# Get terminologies registered by 09-16-2025.
NHL_Glossary_09_16_2025 <- get_glossary() %>% 
  arrange(id)
write_csv(NHL_Glossary_09_16_2025, 'data/other/NHL_Glossary_09_16_2025.csv')
