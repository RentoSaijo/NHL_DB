# ----- Section Header ----- # #This is how we do section headers (capitalized).

# Load libraries. #This is how we annotate each "chunk" of code in the sections (sentence; no articles like "the" or "a").
library(tidyverse)
library(tidymodels)
library(ISLR2)

# Load datasets.
boston <- ISLR2::Boston
auto   <- ISLR2::Auto

# ----- Additional Notes ---- #

#1. Always use "::" notation when referencing a package's function or dataset.
#2. In code, our primary quotation marks are singular ('') whereas in comments, they are double ("").
#3. Helper functions need their own section (and therefore section headers as well) and each function should always have the "chunk" annotation like shown above.
#4. Use "<-" for assignment operator and "=" for argument operator, and try to align these across close lines so that they look visually pleasing.
#5. Between each "chunk" of code, there should be an empty line followed by the next chunk's annotation like shown above.
#6. Within each "chunk" of code, there shouldn't be empty lines as shown above.
#7. "Chunks" of code can have "chunks" inside of them as well, if sufficiently complex.
