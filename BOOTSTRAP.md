# Local Historical Bootstrap

These commands reset the live HuggingFace dataset files, scrape historical parquet files locally through games completed on May 15, 2026, and validate the local output. Do not upload the bootstrap output until validation passes.

## Reset HuggingFace

This keeps the `RentoSaijo/NHL_DB` dataset repo and URL, but deletes the current files in it.

```sh
export HF_REPO='RentoSaijo/NHL_DB'

hf auth login

hf repo-files delete "$HF_REPO" '*' \
  --repo-type dataset \
  --commit-message 'Reset NHL_DB before parquet rebuild'
```

## Common Setup

Run this setup in each terminal session.

```sh
cd /Users/rsai_91/Desktop/Other/Projects/NHL_DB

export NHL_DB_OUTPUT_DIR="$PWD/output-bootstrap-2026-05-15"
export NHL_DB_UPDATE_DATE='2026-05-16'
export NHL_DB_TIMEZONE='America/New_York'
export NHL_DB_OFFLINE_SOURCE='true'

mkdir -p "$NHL_DB_OUTPUT_DIR"
```

`2026-05-16` is intentional because the scripts scrape games where `gameDate < NHL_DB_UPDATE_DATE`.

## Season Shards

Run once in each terminal after the common setup.

```sh
RAW_1=$(Rscript -e 'library(nhlscraper); x <- seasons()$seasonId; cat(paste(x[1:27], collapse=","))')
RAW_2=$(Rscript -e 'library(nhlscraper); x <- seasons()$seasonId; cat(paste(x[28:54], collapse=","))')
RAW_3=$(Rscript -e 'library(nhlscraper); x <- seasons()$seasonId; cat(paste(x[55:81], collapse=","))')
RAW_4=$(Rscript -e 'library(nhlscraper); x <- seasons()$seasonId; cat(paste(x[82:108], collapse=","))')
MODERN='20102011,20112012,20122013,20132014,20142015,20152016,20162017,20172018,20182019,20192020,20202021,20212022,20222023,20232024,20242025,20252026'
REPLAYS_2023='20232024'
REPLAYS_2024='20242025'
REPLAYS_2025='20252026'
```

## Parallel Scrape Commands

Run these in separate terminal sessions.

```sh
Rscript R/game.R --datasets=gc_raw,wsc_raw --seasons="$RAW_1"
```

```sh
Rscript R/game.R --datasets=gc_raw,wsc_raw --seasons="$RAW_2"
```

```sh
Rscript R/game.R --datasets=gc_raw,wsc_raw --seasons="$RAW_3"
```

```sh
Rscript R/game.R --datasets=gc_raw,wsc_raw --seasons="$RAW_4"
```

```sh
Rscript R/game.R --datasets=gc,wsc --seasons="$MODERN"
```

```sh
Rscript R/game.R --datasets=scs,scss --seasons="$MODERN"
```

Run replays only after cleaned GC play-by-plays have finished. These can run in three separate terminal sessions because each season writes to its own parquet file.

```sh
Rscript R/event.R --seasons="$REPLAYS_2023"
```

```sh
Rscript R/event.R --seasons="$REPLAYS_2024"
```

```sh
Rscript R/event.R --seasons="$REPLAYS_2025"
```

## Validate Before Upload

This should print nothing.

```sh
find "$NHL_DB_OUTPUT_DIR" -type f \( -name '*.csv' -o -name '*.csv.gz' \)
```

All parquet files should read successfully.

```sh
Rscript -e '
files <- list.files(Sys.getenv("NHL_DB_OUTPUT_DIR"), recursive = TRUE, full.names = TRUE)
files <- files[endsWith(files, ".parquet")]
stopifnot(length(files) > 0)
invisible(lapply(files, arrow::read_parquet))
cat(length(files), "parquet files readable\n")
'
```
