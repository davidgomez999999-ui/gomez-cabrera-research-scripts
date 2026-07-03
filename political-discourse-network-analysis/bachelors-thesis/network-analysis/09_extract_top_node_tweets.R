# ==============================================================================
# 09_extract_top_node_tweets.R
# ==============================================================================
# Extracts the highest-engagement tweet for each top node identified in
# 08_node_centrality.R, and joins it with centrality data for IQD coding.
#
# Engagement is defined as: n_likes + n_retuits + n_respuestas
# One tweet per node is selected (no ties).
#
# Input:   nodos_IQD_todos.csv     (output of 08_node_centrality.R)
#          data_PSOE.csv, data_PP.csv, data_VOX.csv, data_PODEMOS.csv
#          (outputs of 02_clean_data.R, placed in working directory)
# Output:  tweets_IQD_codificacion.csv
#          (one row per top node, with tweet text and engagement metrics,
#           ready for IQD coding)
#
# Dependencies: dplyr, readr, purrr
#
# Version: 1.0 — as used in the Bachelor's Thesis (2026)
# Author:  David Gómez Cabrera (2026)
# License: MIT — https://opensource.org/licenses/MIT
# ==============================================================================

library(dplyr)
library(readr)
library(purrr)


# ==============================================================================
# 1. LOAD TARGET NODES
# ==============================================================================

nodes <- read_csv("nodos_IQD_todos.csv",
                  col_types = cols(.default = "c"))

parties <- c("PSOE", "PP", "VOX", "PODEMOS")


# ==============================================================================
# 2. EXTRACT TOP TWEET PER NODE
# ==============================================================================

top_tweets <- map_dfr(parties, function(party) {

  target_handles <- nodes %>%
    filter(party == !!party) %>%
    pull(top_node)

  corpus <- read_csv(
    paste0("data_", party, ".csv"),
    col_types = cols(.default = "c")
  ) %>%
    mutate(
      n_likes      = as.numeric(n_likes),
      n_retuits    = as.numeric(n_retuits),
      n_respuestas = as.numeric(n_respuestas),
      engagement   = n_likes + n_retuits + n_respuestas
    )

  corpus %>%
    filter(usuario_handle %in% target_handles) %>%
    group_by(usuario_handle) %>%
    slice_max(engagement, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    mutate(party = party)
})


# ==============================================================================
# 3. JOIN WITH CENTRALITY DATA
# ==============================================================================

output <- nodes %>%
  left_join(top_tweets,
            by = c("top_node" = "usuario_handle", "party" = "party")) %>%
  select(party, comunidad_id, top_node, T, Cg, score,
         tweet_id, texto_tweet, engagement,
         n_likes, n_retuits, n_respuestas,
         nivel, enlace_tweet, parent_tweet_id)


# ==============================================================================
# 4. VERIFICATION
# ==============================================================================

missing_tweets <- output %>% filter(is.na(tweet_id))
if (nrow(missing_tweets) > 0) {
  cat("\nWARNING — nodes without tweet in corpus:\n")
  print(missing_tweets %>% select(party, top_node))
}

cat("\nTotal tweets extracted:", sum(!is.na(output$tweet_id)),
    "of", nrow(output), "\n")


# ==============================================================================
# 5. EXPORT
# ==============================================================================

write_csv(output, "tweets_IQD_codificacion.csv")
cat("Exported: tweets_IQD_codificacion.csv\n")
