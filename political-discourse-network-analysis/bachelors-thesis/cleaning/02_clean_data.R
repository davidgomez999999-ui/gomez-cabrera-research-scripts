# ==============================================================================
# 02_clean_data.R
# ==============================================================================
# Cleans raw corpus data extracted by 01_extract_corpus.py.
# Removes duplicates, corrects known encoding artefacts, normalises missing
# values, and reconstructs hierarchical levels from parent_tweet_id.
#
# Input:   raw_data_{PARTY}.csv   (output of 01_extract_corpus.py)
# Output:  data_{PARTY}.csv       (clean corpus ready for analysis)
#
# Usage:
#   Run interactively in R or RStudio.
#   The script prompts for party name and confirms before executing.
#
# Known issues (v1.0):
#   - n_likes is multiplied by 1000 in the raw extractor output and is
#     corrected here by dividing by 1000. Verified on PSOE corpus; assumed
#     systematic across all ecosystems.
#   - Manual corrections for specific tweet IDs can be added in Section 2.4.
#
# Dependencies: base R only (no external packages required)
#
# Version: 1.0 — as used in the Bachelor's Thesis corpus (2026)
# Author:  David Gómez Cabrera (2026)
# License: MIT — https://opensource.org/licenses/MIT
# ==============================================================================


# ==============================================================================
# INTERACTIVE PARAMETERS
# ==============================================================================

cat("\n", strrep("=", 55), "\n")
cat("  02_clean_data.R\n")
cat(strrep("=", 55), "\n\n")

party <- toupper(trimws(readline("Party [PSOE / PP / VOX / PODEMOS]: ")))
while (!party %in% c("PSOE", "PP", "VOX", "PODEMOS")) {
  cat("Invalid value. Enter one of: PSOE, PP, VOX, PODEMOS\n")
  party <- toupper(trimws(readline("Party [PSOE / PP / VOX / PODEMOS]: ")))
}

input_file  <- paste0("raw_data_", party, ".csv")
output_file <- paste0("data_", party, ".csv")

cat("\n", strrep("-", 55), "\n")
cat("  Party  :", party,       "\n")
cat("  Input  :", input_file,  "\n")
cat("  Output :", output_file, "\n")
cat(strrep("-", 55), "\n\n")

confirm <- toupper(trimws(readline("Confirm? [Y/N]: ")))
while (!confirm %in% c("Y", "N")) {
  confirm <- toupper(trimws(readline("Confirm? [Y/N]: ")))
}
if (confirm == "N") stop("Execution cancelled by user.")

if (!file.exists(input_file)) {
  stop(paste("File not found:", input_file,
             "\nEnsure the CSV is in the working directory."))
}

cat("\nStarting...\n\n")


# ==============================================================================
# 1. IMPORT
# ==============================================================================
# Tweet IDs have 19 digits, exceeding R's exact floating-point precision
# (2^53 ~ 16 digits). Reading them as numeric silently rounds them.
# colClasses forces character on all three ID columns.

raw_data <- read.csv(
  input_file,
  stringsAsFactors = FALSE,
  colClasses = c(
    tweet_id        = "character",
    seed_tweet_id   = "character",
    parent_tweet_id = "character"
  )
)

data <- raw_data
cat("Corpus loaded:", nrow(data), "tweets\n\n")


# ==============================================================================
# 2. CLEANING
# ==============================================================================

# --- 2.1 Remove duplicates ----------------------------------------------------
# Uniqueness criterion: tweet_id.
# If a tweet appears more than once due to overlapping captures, keep first row.

data <- data[!duplicated(data$tweet_id), ]


# --- 2.2 Correct n_likes scale ------------------------------------------------
# n_likes is multiplied by 1000 in the raw extractor output.
# n_respuestas and n_retuits are correct and require no adjustment.

data$n_likes <- data$n_likes / 1000


# --- 2.3 Normalise empty parent_tweet_id to NA --------------------------------
# read.csv reads absent parent_tweet_id as "" due to mixed column content.
# Converted to NA for correct behaviour in downstream operations.

data$parent_tweet_id[data$parent_tweet_id == ""] <- NA


# --- 2.4 Manual point corrections ---------------------------------------------
# Space for corrections identified during manual corpus audit.
# Document each correction with its justification for traceability.
# Format:
#   data$parent_tweet_id[data$tweet_id == "XXXXXXXXXXXXXXXXXX"] <- "YYYYYYYYYYYYYYYYYY"
#   data$usuario_responde_a[data$tweet_id == "XXXXXXXXXXXXXXXXXX"] <- "@handle"



# --- 2.5 Reconstruct missing hierarchical levels ------------------------------
# For each row with nivel == NA, locate its parent and assign parent level + 1.
# Repeats until no resolvable NAs remain.
# Corrections in 2.4 must precede this loop: without parent_tweet_id assigned,
# corrected tweets and all their dependents remain NA regardless of iterations.

repeat {
  idx_na <- which(is.na(data$nivel))
  if (length(idx_na) == 0) break

  idx_parent   <- match(data$parent_tweet_id[idx_na], data$tweet_id)
  nivel_parent <- data$nivel[idx_parent]

  resolvable <- !is.na(idx_parent) & !is.na(nivel_parent)
  if (!any(resolvable)) break

  data$nivel[idx_na[resolvable]] <- as.integer(nivel_parent[resolvable]) + 1L
}


# ==============================================================================
# 3. DIAGNOSTICS
# ==============================================================================

cat("=== DIAGNOSTICS —", paste0("data_", party, ".csv"), "===\n")
cat("Total tweets:              ", nrow(data), "\n")
cat("  → Seed (level 0):        ", sum(data$tipo_interaccion == "seed",      na.rm = TRUE), "\n")
cat("  → Replies:               ", sum(data$tipo_interaccion == "respuesta", na.rm = TRUE), "\n")
cat("  → Distinct users:        ", length(unique(data$usuario_handle)),                     "\n")
cat("  → Maximum depth:         ", max(data$nivel, na.rm = TRUE),                           "\n")

cat("\nIntegrity checks:\n")
cat("  → Tweets without text:             ",
    sum(is.na(data$texto_tweet) | trimws(data$texto_tweet) == ""),
    " — retained; exclude from IQD coding\n")
cat("  → Tweets with unassigned level:    ",
    sum(is.na(data$nivel)),
    " — should be 0\n")
cat("  → Tweets with parent outside corpus:",
    sum(!is.na(data$parent_tweet_id) &
          !(data$parent_tweet_id %in% data$tweet_id)),
    " — uncaptured branches\n")

cat("\nDistribution by hierarchical level:\n")
print(table(data$nivel, useNA = "ifany"))


# ==============================================================================
# 4. EXPORT
# ==============================================================================
# Output is written to the working directory.
# Set your working directory before running (setwd() or RStudio's Session menu).

write.csv(data,
          file         = output_file,
          row.names    = FALSE,
          fileEncoding = "UTF-8")

cat("\n✓ Exported:", output_file, "\n")
