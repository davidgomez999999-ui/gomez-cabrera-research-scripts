# ==============================================================================
# 11_endorsement_reply_ratio.R
# ==============================================================================
# Computes the endorsement-to-reply ratio for each political ecosystem.
# This ratio is reported in the Commentary "Inscription Bias and Discursive
# Capacity on X"
#
# Ratio definition:
#   refrendo = n_likes + n_retuits (silent endorsement affordances)
#   respuestas_directas = direct replies to the seed tweet (level 1)
#   ratio = refrendo / respuestas_directas
#
# Methodological note:
#   Quote-tweets are excluded from the endorsement count. Only likes and
#   simple reposts are included, as these are the affordances that require
#   no text production, operationalising the inscription bias argument.
#
# Input:   data_PSOE.csv, data_PP.csv, data_VOX.csv, data_PODEMOS.csv
#          (outputs of 02_clean_data.R, placed in working directory)
# Output:  ratio_refrendo_respuestas_resultado.csv
#
# Dependencies: tidyverse
#
# Version: 1.0 — as used in the Commentary (2026)
# Author:  David Gómez Cabrera (2026)
# License: MIT — https://opensource.org/licenses/MIT
# ==============================================================================

library(tidyverse)


# ==============================================================================
# CONFIGURATION
# ==============================================================================

parties <- c("PSOE", "PP", "VOX", "PODEMOS")


# ==============================================================================
# 1. SAFE CORPUS READER
# ==============================================================================

load_corpus <- function(path) {
  df <- read_csv(path, col_types = cols(.default = col_character()),
                 show_col_types = FALSE)
  if (ncol(df) == 1) {
    df <- read_csv2(path, col_types = cols(.default = col_character()),
                    show_col_types = FALSE)
  }
  df
}


# ==============================================================================
# 2. COMPUTE RATIO PER ECOSYSTEM
# ==============================================================================

compute_ratio <- function(party) {
  path <- paste0("data_", party, ".csv")
  df   <- load_corpus(path)

  # Detect seed tweet ID from the corpus itself
  seed_id <- df %>%
    filter(!is.na(seed_tweet_id), seed_tweet_id != "") %>%
    count(seed_tweet_id, sort = TRUE) %>%
    slice(1) %>%
    pull(seed_tweet_id)

  # Seed row (for endorsement metrics)
  seed_row <- df %>% filter(tweet_id == seed_id)

  # Direct replies: tweets whose parent is the seed (excluding seed itself)
  direct_by_parent <- df %>%
    filter(parent_tweet_id == seed_id, tweet_id != seed_id) %>%
    nrow()

  # Cross-check: tweets at level 1
  direct_by_level <- df %>%
    filter(nivel == "1") %>%
    nrow()

  tibble(
    ecosystem            = party,
    seed_detected        = seed_id,
    seed_in_corpus       = nrow(seed_row) == 1,
    likes                = as.numeric(seed_row$n_likes[1]),
    reposts              = as.numeric(seed_row$n_retuits[1]),
    endorsement          = likes + reposts,
    direct_replies       = direct_by_parent,
    check_level1         = direct_by_level,
    ratio                = endorsement / direct_replies
  )
}

results <- map_dfr(parties, compute_ratio)
print(results, width = Inf)


# ==============================================================================
# 3. INTEGRITY CHECKS
# ==============================================================================

stopifnot("Seed missing from one or more corpora" = all(results$seed_in_corpus))
stopifnot("NA endorsement metrics in seed row"    = !any(is.na(results$endorsement)))
stopifnot("Zero direct replies in one or more corpora" = all(results$direct_replies > 0))

if (!all(results$direct_replies == results$check_level1)) {
  warning("Direct replies by parent_tweet_id and by nivel==1 do not match — review before use.")
}


# ==============================================================================
# 4. REPORTED RANGE (as cited in the Commentary)
# ==============================================================================

cat(sprintf("\nEndorsement-to-reply ratio range: between %s:1 and %s:1\n",
            format(round(min(results$ratio))),
            format(round(max(results$ratio)))))


# ==============================================================================
# 5. EXPORT
# ==============================================================================

write_csv(results, "ratio_refrendo_respuestas_resultado.csv")
cat("Exported: ratio_refrendo_respuestas_resultado.csv\n")
