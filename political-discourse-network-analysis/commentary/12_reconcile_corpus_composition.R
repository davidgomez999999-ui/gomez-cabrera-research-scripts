# ==============================================================================
# 12_reconcile_corpus_composition.R
# ==============================================================================
# Reconciles the full corpus size (2,928 messages) with the direct-reply
# counts reported in Table 1 (1,493 messages) of the Commentary
# "The silence of agreement: Asymmetric affordances and the over-representation
# of conflict in X's textual corpora" (submitted to Big Data & Society, 2026).
#
# Classification (mutually exclusive, in priority order):
#   seed_post     = the seed tweet itself
#   quote_tweet   = quote of the seed (via type column, if one exists)
#   direct_reply  = parent_tweet_id == seed tweet ID (level-1 replies)
#   deeper_reply  = parent_tweet_id points to another tweet in the thread
#   unclassified  = residual (should be empty; inspect if not)
#
# Integrity checks:
#   Per-seed direct replies and endorsement mass are compared against the
#   values published in Table 1 (340/358/458/337; 26,988/9,865/36,209/59,475),
#   and total rows against the reported corpus size (2,928).
#
# Input:   data_PSOE.csv, data_PP.csv, data_VOX.csv, data_PODEMOS.csv
#          (outputs of 02_clean_data.R, placed in working directory)
# Output:  composicion_corpus_resultado.csv
#
# Dependencies: tidyverse
#
# Version: 1.0 - as used in the Commentary (2026)
# Author:  David Gómez Cabrera (2026)
# License: MIT - https://opensource.org/licenses/MIT
# ==============================================================================

library(tidyverse)


# ==============================================================================
# CONFIGURATION
# ==============================================================================

parties <- c("PSOE", "PP", "VOX", "PODEMOS")

# Values published in Table 1 of the manuscript (integrity targets)
expected <- tribble(
  ~ecosystem, ~direct_expected, ~endorsement_expected,
  "PODEMOS",  340L,             26988,
  "PP",       358L,             9865,
  "PSOE",     458L,             36209,
  "VOX",      337L,             59475
)
expected_total_rows   <- 2928
expected_total_direct <- 1493


# ==============================================================================
# 1. SAFE CORPUS READER (same as 11_endorsement_reply_ratio.R)
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
# 2. CLASSIFY EVERY RECORD BY ITS RELATION TO THE SEED
# ==============================================================================

classify_corpus <- function(party) {
  path <- paste0("data_", party, ".csv")
  df   <- load_corpus(path)

  # Detect seed tweet ID from the corpus itself
  seed_id <- df %>%
    filter(!is.na(seed_tweet_id), seed_tweet_id != "") %>%
    count(seed_tweet_id, sort = TRUE) %>%
    slice(1) %>%
    pull(seed_tweet_id)

  # Detect a tweet-type column, if the cleaning pipeline kept one
  type_candidates <- c("tipo", "type", "tweet_type", "reference_type",
                       "referenced_type", "relacion")
  type_col <- intersect(type_candidates, names(df))
  type_col <- if (length(type_col) > 0) type_col[1] else NA_character_

  quote_flag <- if (!is.na(type_col)) {
    replace_na(str_detect(str_to_lower(df[[type_col]]), "quot|cita"), FALSE)
  } else {
    rep(FALSE, nrow(df))
  }

  df <- df %>%
    mutate(
      .quote          = quote_flag,
      .parent_missing = is.na(parent_tweet_id) | parent_tweet_id == "",
      category = case_when(
        tweet_id == seed_id                           ~ "seed_post",
        .quote                                        ~ "quote_tweet",
        !.parent_missing & parent_tweet_id == seed_id ~ "direct_reply",
        !.parent_missing & parent_tweet_id != seed_id ~ "deeper_reply",
        TRUE                                          ~ "unclassified"
      ),
      ecosystem = party
    )

  cat("\n============ ", party, " ============\n")
  cat("Seed detected:", seed_id, "\n")
  cat("Type column:", ifelse(is.na(type_col), "none found", type_col), "\n")
  cat("\nCategory x nivel:\n")
  print(table(df$category, df$nivel, useNA = "ifany"))
  if (!is.na(type_col)) {
    cat("\nValues of '", type_col, "':\n", sep = "")
    print(table(df[[type_col]], useNA = "ifany"))
  }

  df %>% select(ecosystem, tweet_id, category, nivel, n_likes, n_retuits)
}

all_rows <- map_dfr(parties, classify_corpus)


# ==============================================================================
# 3. COMPOSITION TABLE AND TOTALS
# ==============================================================================

composition <- all_rows %>%
  count(ecosystem, category) %>%
  pivot_wider(names_from = category, values_from = n, values_fill = 0)

cat("\n============ COMPOSITION BY ECOSYSTEM ============\n")
print(composition, width = Inf)

cat("\nTotal rows across the four files:", nrow(all_rows),
    "| expected:", expected_total_rows, "\n")

totals_by_cat <- all_rows %>% count(category)
cat("\nTotals by category:\n")
print(totals_by_cat)


# ==============================================================================
# 4. VERIFY EVERY FIGURE IN TABLE 1
# ==============================================================================

endorsement <- all_rows %>%
  filter(category == "seed_post") %>%
  transmute(ecosystem,
            endorsement = as.numeric(n_likes) + as.numeric(n_retuits))

verification <- composition %>%
  select(ecosystem, direct_reply) %>%
  left_join(endorsement, by = "ecosystem") %>%
  left_join(expected,    by = "ecosystem") %>%
  mutate(
    direct_match      = direct_reply == direct_expected,
    endorsement_match = endorsement  == endorsement_expected,
    ratio_recomputed  = round(endorsement / direct_reply)
  )

cat("\n============ TABLE 1 VERIFICATION ============\n")
print(verification, width = Inf)

if (!all(verification$direct_match)) {
  warning("Direct-reply counts do not match Table 1 - inspect Category x nivel above.")
}
if (!all(verification$endorsement_match)) {
  warning("Endorsement masses do not match Table 1 - inspect seed rows.")
}
if (sum(verification$direct_reply) != expected_total_direct) {
  warning("Total direct replies differ from 1,493.")
}


# ==============================================================================
# 5. DRAFT MANUSCRIPT SENTENCE (final wording fixed in revision)
# ==============================================================================

n_by_cat <- deframe(totals_by_cat)
get0n    <- function(k) ifelse(k %in% names(n_by_cat), n_by_cat[[k]], 0L)

cat(sprintf(paste0(
  "\nDraft:\n\"The %d-message corpus comprises %d direct replies to the four ",
  "seeds, %d quote-tweets, %d deeper-level replies and %d seed posts; the ",
  "ratios in Table 1 use direct replies as the denominator.\"\n"),
  nrow(all_rows), get0n("direct_reply"), get0n("quote_tweet"),
  get0n("deeper_reply"), get0n("seed_post")))

if (get0n("unclassified") > 0) {
  cat("\nWARNING:", get0n("unclassified"),
      "rows remain unclassified - do not use the draft sentence yet.\n")
}


# ==============================================================================
# 6. EXPORT
# ==============================================================================

write_csv(composition, "composicion_corpus_resultado.csv")
cat("\nExported: composicion_corpus_resultado.csv\n")
