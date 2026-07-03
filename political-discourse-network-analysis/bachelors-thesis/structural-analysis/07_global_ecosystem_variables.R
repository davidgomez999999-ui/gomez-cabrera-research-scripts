# ==============================================================================
# 07_global_ecosystem_variables.R
# ==============================================================================
# Computes cross-ecosystem structural variables (Level 4) by analysing
# user presence across the four political ecosystems.
#
# Variables computed:
#   Po_ext : external porosity — proportion of unique users appearing in
#             more than one ecosystem
#   Fr_ext : external fragmentation — proportion of ecosystem pairs with
#             no shared users (out of 6 possible pairs)
#   Ab_ext : external bridge actors — number of users present in 2+
#             ecosystems, with full listing
#
# Note: seed nodes are included here (unlike in 06_structural_variables.R
# where they were excluded from Louvain detection). In Level 4 there is no
# community detection: only cross-ecosystem user presence is computed.
# Excluding seeds would suppress empirically relevant information about
# actor participation across ecosystems.
#
# Input:   grafo_nodos_PSOE.csv, grafo_nodos_PP.csv,
#          grafo_nodos_VOX.csv,  grafo_nodos_PODEMOS.csv
#          (outputs of 06_structural_variables.R, placed in working directory)
# Output:  data_ecosistema_global.csv
#          data_pares_ecosistemas.csv
#          data_actores_puente_ext.csv
#
# Dependencies: dplyr, readr
#
# Version: 1.0 — as used in the Bachelor's Thesis (2026)
# Author:  David Gómez Cabrera (2026)
# License: MIT — https://opensource.org/licenses/MIT
# ==============================================================================

library(dplyr)
library(readr)


# ==============================================================================
# 1. LOAD NODE FILES BY ECOSYSTEM
# ==============================================================================

actors <- c("PSOE", "PP", "VOX", "PODEMOS")

nodes <- lapply(actors, function(a) {
  path <- paste0("grafo_nodos_", a, ".csv")
  df   <- read_csv(path, show_col_types = FALSE)
  df %>%
    select(usuario_handle) %>%
    distinct() %>%
    rename(Label = usuario_handle) %>%
    mutate(ecosystem = a)
}) %>% bind_rows()


# ==============================================================================
# 2. USER × ECOSYSTEM PRESENCE TABLE
# ==============================================================================

presence <- nodes %>%
  distinct(Label, ecosystem) %>%
  group_by(Label) %>%
  summarise(
    n_ecosystems = n_distinct(ecosystem),
    ecosystems   = paste(sort(unique(ecosystem)), collapse = "-"),
    .groups = "drop"
  )


# ==============================================================================
# 3. Po_ext — EXTERNAL POROSITY
# ==============================================================================

n_users_total <- nrow(presence)
n_bridge      <- sum(presence$n_ecosystems > 1)
Po_ext        <- n_bridge / n_users_total


# ==============================================================================
# 4. Fr_ext — EXTERNAL FRAGMENTATION
# ==============================================================================

pairs <- combn(actors, 2, simplify = FALSE)

pairs_no_overlap <- sapply(pairs, function(pair) {
  users_a <- nodes %>% filter(ecosystem == pair[1]) %>% pull(Label)
  users_b <- nodes %>% filter(ecosystem == pair[2]) %>% pull(Label)
  length(intersect(users_a, users_b)) == 0
})

Fr_ext <- sum(pairs_no_overlap) / length(pairs)

pair_detail <- tibble(
  pair              = sapply(pairs, paste, collapse = "-"),
  shared_users      = sapply(pairs, function(pair) {
    users_a <- nodes %>% filter(ecosystem == pair[1]) %>% pull(Label)
    users_b <- nodes %>% filter(ecosystem == pair[2]) %>% pull(Label)
    length(intersect(users_a, users_b))
  }),
  no_overlap = pairs_no_overlap
)


# ==============================================================================
# 5. Ab_ext — EXTERNAL BRIDGE ACTORS
# ==============================================================================

Ab_ext_list <- presence %>%
  filter(n_ecosystems > 1) %>%
  arrange(desc(n_ecosystems), Label)

Ab_ext <- nrow(Ab_ext_list)


# ==============================================================================
# 6. CONSOLE SUMMARY
# ==============================================================================

cat("\n", strrep("=", 55), "\n")
cat(" SUMMARY LEVEL 4 — Global discursive ecosystem\n")
cat(strrep("=", 55), "\n\n")
cat(sprintf("Total unique users:             %d\n", n_users_total))
cat(sprintf("Users in >1 ecosystem:          %d\n", n_bridge))
cat(sprintf("Po_ext:                         %.4f\n", Po_ext))
cat(sprintf("Fr_ext:                         %.4f\n", Fr_ext))
cat(sprintf("Ab_ext (bridge actors):         %d\n\n", Ab_ext))
cat("Detail by ecosystem pair:\n")
print(pair_detail)
cat("\nExternal bridge actors:\n")
print(Ab_ext_list)


# ==============================================================================
# 7. EXPORT
# ==============================================================================

data_ecosistema_global <- tibble(
  n_users_total = n_users_total,
  n_bridge_ext  = n_bridge,
  Po_ext        = Po_ext,
  Fr_ext        = Fr_ext,
  Ab_ext        = Ab_ext
)

write_csv(data_ecosistema_global, "data_ecosistema_global.csv")
write_csv(pair_detail,            "data_pares_ecosistemas.csv")
write_csv(Ab_ext_list,            "data_actores_puente_ext.csv")

cat("\n✓ Export complete: 3 files written to working directory\n")
cat("  data_ecosistema_global.csv\n")
cat("  data_pares_ecosistemas.csv\n")
cat("  data_actores_puente_ext.csv\n")
