# ==============================================================================
# 03_build_corpus.R
# ==============================================================================
# Merges the four cleaned party corpora into a single analytical dataset.
# Excludes seed tweets (level 0), which are not coded in the IQD pipeline.
# Adds an 'actor' column identifying the political ecosystem of each tweet.
#
# Input:   data_PSOE.csv, data_PP.csv, data_VOX.csv, data_PODEMOS.csv
#          (outputs of 02_clean_data.R, placed in the working directory)
# Output:  corpus_completo.csv
#          (unified corpus ready for IQD pipeline input)
#
# Dependencies: dplyr
#
# Version: 1.0 — as used in the Bachelor's Thesis corpus (2026)
# Author:  David Gómez Cabrera (2026)
# License: MIT — https://opensource.org/licenses/MIT
# ==============================================================================

library(dplyr)


# ==============================================================================
# 1. SAFE CORPUS READER
# ==============================================================================
# Tweet IDs exceed R's floating-point precision (19 digits vs 2^53 ~ 16).
# This function auto-detects all *_id columns and forces them to character,
# preventing silent numeric truncation.

read_corpus <- function(file) {
  header  <- read.csv(file, nrows = 1, stringsAsFactors = FALSE)
  cols    <- names(header)
  classes <- setNames(rep(NA_character_, length(cols)), cols)
  classes[grepl("_id", cols, ignore.case = TRUE)] <- "character"
  read.csv(file, stringsAsFactors = FALSE, colClasses = classes)
}


# ==============================================================================
# 2. LOAD PARTY CORPORA
# ==============================================================================
# Files are expected in the working directory.
# Set your working directory before running (setwd() or RStudio's Session menu).

psoe    <- read_corpus("data_PSOE.csv");    psoe$actor    <- "PSOE"
pp      <- read_corpus("data_PP.csv");      pp$actor      <- "PP"
vox     <- read_corpus("data_VOX.csv");     vox$actor     <- "VOX"
podemos <- read_corpus("data_PODEMOS.csv"); podemos$actor <- "PODEMOS"


# ==============================================================================
# 3. MERGE AND FILTER
# ==============================================================================
# Seed tweets (nivel == 0) are excluded: they are not reply interactions
# and are not subject to IQD coding.

corpus_completo <- bind_rows(psoe, pp, vox, podemos) %>%
  filter(nivel != 0)


# ==============================================================================
# 4. VERIFICATION
# ==============================================================================

cat("=== CORPUS VERIFICATION ===\n")
cat("Total tweets (nivel != 0):", nrow(corpus_completo), "\n")
cat("\nDistribution by actor:\n")
print(table(corpus_completo$actor))
cat("\ntweet_id class:", class(corpus_completo$tweet_id), "\n")
cat("tweet_id example:", corpus_completo$tweet_id[1], "\n")
cat("tweet_id characters:", nchar(corpus_completo$tweet_id[1]), "\n")

cat("\nReferential integrity (parent_tweet_id in corpus):\n")
all_ids    <- corpus_completo$tweet_id
integrity  <- corpus_completo %>%
  filter(nivel >= 2) %>%
  summarise(
    total          = n(),
    parent_found   = sum(parent_tweet_id %in% all_ids),
    parent_missing = sum(!(parent_tweet_id %in% all_ids))
  )
print(integrity)


# ==============================================================================
# 5. EXPORT
# ==============================================================================

write.csv(corpus_completo,
          "corpus_completo.csv",
          row.names = FALSE,
          quote     = TRUE)

cat("\n=== EXPORTED ===\n")
cat("File: corpus_completo.csv\n")
cat("Tweets:", nrow(corpus_completo), "\n")
cat("Columns:", ncol(corpus_completo), "\n")
cat("\ncorpus_completo.csv ready for IQD pipeline input.\n")
