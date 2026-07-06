# ==============================================================================
# 13_export_structural_corpus.R
# ==============================================================================
# Exports the deposit-ready structural corpus for the Commentary
# "The silence of agreement: Asymmetric affordances and the over-representation
# of conflict in X's textual corpora" (submitted to Big Data & Society, 2026).
#
# The export keeps the six columns used by scripts 11 and 12 - tweet_id,
# seed_tweet_id, parent_tweet_id, nivel, n_likes, n_retuits - and drops all
# content and identity fields (no tweet text, no user handles), in line with
# the article's ethical statement. Output files keep the original names
# (data_PARTY.csv) so that scripts 11 and 12 run unmodified on the
# deposited data.
#
# Input:   data_PSOE.csv, data_PP.csv, data_VOX.csv, data_PODEMOS.csv
#          (outputs of 02_clean_data.R, placed in working directory)
# Output:  zenodo_deposit/data_*.csv, CHECKSUMS.md5, README_DRAFT.md
#
# Dependencies: tidyverse
#
# Version: 1.1 - deposit contents aligned with the submitted manuscript (2026)
# Author:  David Gómez Cabrera (2026)
# License: MIT - https://opensource.org/licenses/MIT
# ==============================================================================

library(tidyverse)


# ==============================================================================
# CONFIGURATION
# ==============================================================================

parties <- c("PSOE", "PP", "VOX", "PODEMOS")

STRUCTURAL_COLS <- c("tweet_id", "seed_tweet_id", "parent_tweet_id",
                     "nivel", "n_likes", "n_retuits")

EXPECTED_TOTAL_ROWS <- 2928


# ==============================================================================
# 1. SAFE CORPUS READER (same as 11 / 12)
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
# 2. EXPORT STRUCTURAL FILES
# ==============================================================================

dir.create("zenodo_deposit", showWarnings = FALSE)

total_rows <- 0

for (p in parties) {
  infile  <- paste0("data_", p, ".csv")
  outfile <- file.path("zenodo_deposit", paste0("data_", p, ".csv"))

  df <- load_corpus(infile)

  missing <- setdiff(STRUCTURAL_COLS, names(df))
  if (length(missing) > 0) {
    stop("Missing structural columns in ", infile, ": ",
         paste(missing, collapse = ", "))
  }

  out <- df %>% select(all_of(STRUCTURAL_COLS))

  # Safety net: assert nothing but the six structural columns is exported
  stopifnot(identical(names(out), STRUCTURAL_COLS))

  write_csv(out, outfile)
  total_rows <- total_rows + nrow(out)

  cat(sprintf("%-22s %5d rows  ->  %s\n", infile, nrow(out), outfile))
}

cat("\nTotal rows exported:", total_rows,
    "| expected:", EXPECTED_TOTAL_ROWS, "\n")
if (total_rows != EXPECTED_TOTAL_ROWS) {
  warning("Row total differs from the corpus size reported in the manuscript.")
}


# ==============================================================================
# 3. CHECKSUMS
# ==============================================================================

files <- list.files("zenodo_deposit", pattern = "^data_.*\\.csv$",
                    full.names = TRUE)
sums  <- tools::md5sum(files)
writeLines(paste(sums, basename(names(sums))),
           file.path("zenodo_deposit", "CHECKSUMS.md5"))
cat("\nCHECKSUMS.md5 written.\n")


# ==============================================================================
# 4. README DRAFT (complete the [PENDING] fields on deposit day)
# ==============================================================================

readme <- c(
"# Reply corpus (structural data)",
"",
"Supplementary deposit for the Commentary \"The silence of agreement:",
"Asymmetric affordances and the over-representation of conflict in X's",
"textual corpora\" (submitted to Big Data & Society, 2026).",
"",
"## Contents",
"- data_PSOE.csv, data_PP.csv, data_VOX.csv, data_PODEMOS.csv - structural",
"  reply corpus: 2,928 records across four seed threads collected on X in",
"  January 2026.",
"- CHECKSUMS.md5 - integrity checksums for the four data files.",
"",
"## Data description",
"Each row is one message. Columns: tweet_id (message identifier, string);",
"seed_tweet_id (identifier of the thread's seed post); parent_tweet_id",
"(identifier of the message replied to); nivel (depth in the reply tree,",
"0 = seed); n_likes; n_retuits. Read all identifiers as strings to avoid",
"64-bit float truncation.",
"",
"## Provenance, and what is withheld",
"The deposited files are the output of 13_export_structural_corpus.R applied",
"to the raw capture - the single, declared private step in the chain. The raw",
"capture (message text and user handles) is not redistributed, in line with",
"the article's ethical statement: non-institutional users are pseudonymized",
"and no individual is identified. Reasoned requests for restricted access may",
"be addressed to the author. The corpus originates in the author's Bachelor's",
"Thesis, where the extraction instrument is documented in full.",
"",
"## Replication",
"Scripts 11 (endorsement-to-reply ratios, Table 1) and 12 (corpus composition",
"and Table 1 verification) from the code release [PENDING: GitHub release DOI]",
"run unmodified on these files and reproduce every figure reported in the",
"article.",
"",
"## Related deposits",
"- Walkthrough evidence archive: https://doi.org/10.5281/zenodo.21138832",
"- Bachelor's Thesis (extraction instrument; Discursive Capacity):",
"  https://hdl.handle.net/10481/114519 | https://doi.org/10.5281/zenodo.21138746",
"",
"## License",
"Data: CC BY 4.0. Code (in the linked release): MIT."
)
writeLines(readme, file.path("zenodo_deposit", "README_DRAFT.md"))
cat("README_DRAFT.md written.\n\n")
cat("Deposit folder ready: ./zenodo_deposit/\n")
