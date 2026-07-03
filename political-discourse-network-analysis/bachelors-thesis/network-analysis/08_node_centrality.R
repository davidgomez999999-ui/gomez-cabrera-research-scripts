# ==============================================================================
# 08_node_centrality.R
# ==============================================================================
# Ranks community nodes across all four political ecosystems by a composite
# centrality score combining community size (T) and maximum in-degree (Cg).
# Identifies the top node per community for IQD coding selection.
#
# Selection criterion:
#   score = (T + Cg) / 2
#   Only communities with T >= 10 are included.
#   Top node per community: user with highest in-degree (degree_in).
#
# Input:   grafo_nodos_PSOE.csv, grafo_nodos_PP.csv,
#          grafo_nodos_VOX.csv,  grafo_nodos_PODEMOS.csv
#          (outputs of 06_structural_variables.R, placed in working directory)
# Output:  nodos_IQD_todos.csv
#          (ranked node list across all ecosystems, ready for IQD coding)
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
# PARAMETERS
# ==============================================================================

parties <- c("PSOE", "PP", "VOX", "PODEMOS")
T_MIN   <- 10   # minimum community size for inclusion


# ==============================================================================
# 1. COMPUTE RANKING ACROSS ALL ECOSYSTEMS
# ==============================================================================

ranking <- map_dfr(parties, function(party) {

  nodes <- read_csv(
    paste0("grafo_nodos_", party, ".csv"),
    col_types = cols(.default = "c")
  ) %>%
    mutate(degree_in = as.numeric(degree_in))

  nodes %>%
    filter(tipo_nodo == "community") %>%
    group_by(comunidad_id) %>%
    summarise(
      T        = n(),
      top_node = usuario_handle[which.max(degree_in)],
      Cg       = max(degree_in),
      .groups  = "drop"
    ) %>%
    filter(T >= T_MIN) %>%
    mutate(
      score  = (T + Cg) / 2,
      party  = party
    ) %>%
    arrange(desc(score))
})


# ==============================================================================
# 2. SUMMARY
# ==============================================================================

cat("\n--- Full ranking (all ecosystems) ---\n")
print(ranking, n = Inf)
cat("\nTotal nodes to code:", nrow(ranking), "\n")


# ==============================================================================
# 3. EXPORT
# ==============================================================================

write_csv(ranking, "nodos_IQD_todos.csv")
cat("Exported: nodos_IQD_todos.csv\n")
