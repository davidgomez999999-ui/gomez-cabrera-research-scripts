# ==============================================================================
# 05_stratified_sampling.R
# ==============================================================================
# Draws two independent stratified random samples from the unified corpus
# for IQD coding:
#
#   - Calibration sample: stratified by actor × hierarchical level category
#     (N1, N2, N3+). Used to calibrate the LLM coding prompt.
#     Seed: 8301
#
#   - Validation sample: 50 tweets per actor, drawn from the remaining pool
#     after excluding calibration IDs.
#     Seed: 8302
#
# Input:   data_PSOE.csv, data_PP.csv, data_VOX.csv, data_PODEMOS.csv
#          (outputs of 02_clean_data.R, placed in the working directory)
# Output:  muestra_calibracion_IQD.csv
#          muestra_validacion_IQD.csv
#
# Reproducibility:
#   Seeds are fixed (8301, 8302) and documented here for exact replication.
#   Results are identical across runs given the same input corpora.
#
# Dependencies: dplyr
#
# Version: 1.0 — as used in the Bachelor's Thesis (2026)
#           v2 correction: tweet_id, seed_tweet_id and parent_tweet_id
#           forced to character to prevent numeric truncation.
# Author:  David Gómez Cabrera (2026)
# License: MIT — https://opensource.org/licenses/MIT
# ==============================================================================

library(dplyr)


# ==============================================================================
# 1. SAFE CORPUS READER
# ==============================================================================

read_corpus <- function(file) {
  header  <- read.csv(file, nrows = 1, stringsAsFactors = FALSE)
  cols    <- names(header)
  classes <- setNames(rep(NA_character_, length(cols)), cols)
  classes[grepl("_id", cols, ignore.case = TRUE)] <- "character"
  read.csv(file, stringsAsFactors = FALSE, colClasses = classes)
}


# ==============================================================================
# 2. LOAD CORPORA
# ==============================================================================

psoe    <- read_corpus("data_PSOE.csv");    psoe$actor    <- "PSOE"
pp      <- read_corpus("data_PP.csv");      pp$actor      <- "PP"
vox     <- read_corpus("data_VOX.csv");     vox$actor     <- "VOX"
podemos <- read_corpus("data_PODEMOS.csv"); podemos$actor <- "PODEMOS"

cat("=== ID INTEGRITY CHECK ===\n")
for (df_name in c("psoe", "pp", "vox", "podemos")) {
  df <- get(df_name)
  cat(sprintf("  %-8s tweet_id: class=%s | example=%s | nchar=%d\n",
              toupper(df_name),
              class(df$tweet_id),
              df$tweet_id[1],
              nchar(df$tweet_id[1])))
}
cat("\n")


# ==============================================================================
# 3. MERGE AND STRATIFICATION VARIABLE
# ==============================================================================

corpus <- bind_rows(psoe, pp, vox, podemos)

cat("=== FULL CORPUS SIZE ===\n")
cat("Total tweets (including level 0):", nrow(corpus), "\n")
print(table(corpus$actor, corpus$nivel))

corpus_op <- corpus %>%
  filter(nivel != 0) %>%
  mutate(nivel_cat = case_when(
    nivel == 1 ~ "N1",
    nivel == 2 ~ "N2",
    nivel >= 3 ~ "N3plus"
  )) %>%
  filter(!(is.na(texto_tweet) | texto_tweet == "") | n_respuestas >= 1)

cat("\nOperational corpus (nivel != 0, after text filter):", nrow(corpus_op), "\n")
cat("Distribution by actor and level category:\n")
print(table(corpus_op$actor, corpus_op$nivel_cat))
cat("\n")


# ==============================================================================
# 4. CALIBRATION SAMPLE (seed = 8301)
# ==============================================================================
# Quota table: stratified by actor × nivel_cat.
# Quotas were set proportionally to corpus size per stratum.

quotas_calibration <- data.frame(
  actor     = c("PSOE","PSOE","PSOE",
                "PP",  "PP",  "PP",
                "VOX", "VOX", "VOX",
                "PODEMOS","PODEMOS","PODEMOS"),
  nivel_cat = c("N1","N2","N3plus",
                "N1","N2","N3plus",
                "N1","N2","N3plus",
                "N1","N2","N3plus"),
  n         = c(6, 6, 3,
                10, 3, 2,
                7, 6, 2,
                9, 5, 1)
)

set.seed(8301)

calibration_sample <- do.call(bind_rows, lapply(1:nrow(quotas_calibration), function(i) {
  a  <- quotas_calibration$actor[i]
  nc <- quotas_calibration$nivel_cat[i]
  n  <- quotas_calibration$n[i]
  corpus_op %>%
    filter(actor == a, nivel_cat == nc) %>%
    slice_sample(n = n)
}))

cat("=== CALIBRATION SAMPLE ===\n")
cat("Total tweets:", nrow(calibration_sample), "\n")
print(table(calibration_sample$actor, calibration_sample$nivel_cat))
cat("\n")


# ==============================================================================
# 5. VALIDATION SAMPLE (seed = 8302)
# ==============================================================================
# 50 tweets per actor, drawn from the pool excluding calibration IDs.

ids_calibration  <- calibration_sample$tweet_id
corpus_validation <- corpus_op %>%
  filter(!(tweet_id %in% ids_calibration))

cat("=== VALIDATION POOL (after calibration exclusion) ===\n")
print(table(corpus_validation$actor))
cat("\n")

set.seed(8302)

validation_sample <- corpus_validation %>%
  group_by(actor) %>%
  slice_sample(n = 50) %>%
  ungroup()

cat("=== VALIDATION SAMPLE ===\n")
cat("Total tweets:", nrow(validation_sample), "\n")
print(table(validation_sample$actor))
cat("\n")

overlap <- sum(validation_sample$tweet_id %in% calibration_sample$tweet_id)
cat("Independence check — overlapping IDs:", overlap,
    ifelse(overlap == 0, "(OK)\n\n", "(ERROR — REVIEW)\n\n"))


# ==============================================================================
# 6. EXPORT
# ==============================================================================
# IDs are quoted (quote = TRUE) to prevent downstream tools from
# reinterpreting them as numeric values.

write.csv(calibration_sample,
          "muestra_calibracion_IQD.csv",
          row.names = FALSE,
          quote     = TRUE)

write.csv(validation_sample,
          "muestra_validacion_IQD.csv",
          row.names = FALSE,
          quote     = TRUE)

cat("=== FILES EXPORTED ===\n")
cat("muestra_calibracion_IQD.csv —", nrow(calibration_sample), "tweets\n")
cat("muestra_validacion_IQD.csv  —", nrow(validation_sample),  "tweets\n")
cat("\nPhase 0 complete. Seeds: calibration=8301 | validation=8302\n")
