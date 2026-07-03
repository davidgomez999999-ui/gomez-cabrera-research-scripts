# ==============================================================================
# 06_structural_variables.R
# ==============================================================================
# Computes structural variables at three analytical levels for a single
# political ecosystem (one party per run):
#
#   Level 1 — Tweet:      Ni, V, tiene_hijo, n_hijos, r_i
#   Level 2 — Thread:     N_tweets, n_participantes, Pmax, Pmed, R, Co, HHI
#   Level 3 — Community:  T, D, Cg, Cc, Cb, Po_int, Fr_int, Ab_int
#                         (Louvain community detection on Graph B)
#
# Also exports:
#   grafo_nodos_{PARTY}.csv   — all nodes of Graph B with community membership
#   grafo_aristas_{PARTY}.csv — all edges of Graph B
#
# Input:   data_{PARTY}.csv (output of 02_clean_data.R)
# Output:  data_tweet_{PARTY}.csv
#          data_hilo_{PARTY}.csv
#          data_comunidad_{PARTY}.csv
#          grafo_nodos_{PARTY}.csv
#          grafo_aristas_{PARTY}.csv
#
# Methodological decisions:
#   - Graph B: directed, binary (distinct per pair), self-loops excluded.
#   - Seed node excluded from Graph B: pure sink (0 outgoing edges),
#     which would generate an artificial giant community in Louvain detection.
#   - Cloud nodes (connected only to/from seed) assigned comunidad_id = 0.
#   - Louvain run on undirected version of Graph B. set.seed(2026).
#   - Community density D = m / n(n-1) on directed subgraph; NA for n = 1.
#   - Self-replies: r_i = 0, counted in R denominator as non-reciprocal.
#
# Dependencies: dplyr, readr, igraph
#
# Version: 1.0 — as used in the Bachelor's Thesis (2026)
# Author:  David Gómez Cabrera (2026)
# License: MIT — https://opensource.org/licenses/MIT
# ==============================================================================

library(dplyr)
library(readr)
library(igraph)

set.seed(2026)


# ==============================================================================
# INTERACTIVE PARAMETERS
# ==============================================================================

cat("\n", strrep("=", 55), "\n")
cat("  06_structural_variables.R\n")
cat(strrep("=", 55), "\n\n")

party <- toupper(trimws(readline("Party [PSOE / PP / VOX / PODEMOS]: ")))
while (!party %in% c("PSOE", "PP", "VOX", "PODEMOS")) {
  cat("Invalid value. Enter one of: PSOE, PP, VOX, PODEMOS\n")
  party <- toupper(trimws(readline("Party [PSOE / PP / VOX / PODEMOS]: ")))
}

seed_user <- trimws(readline("Seed actor handle (with @): "))
while (!startsWith(seed_user, "@") || nchar(seed_user) < 2) {
  cat("Handle must start with @ and have at least one character.\n")
  seed_user <- trimws(readline("Seed actor handle (with @): "))
}

seed_id <- trimws(readline("Seed tweet ID: "))
while (nchar(seed_id) == 0) {
  cat("ID cannot be empty.\n")
  seed_id <- trimws(readline("Seed tweet ID: "))
}

input_path <- trimws(readline("Path to input CSV: "))
while (!file.exists(input_path)) {
  cat("File not found. Check the path.\n")
  input_path <- trimws(readline("Path to input CSV: "))
}

cat("\n", strrep("-", 55), "\n")
cat("  Party    :", party,      "\n")
cat("  Seed     :", seed_user,  "\n")
cat("  Seed ID  :", seed_id,    "\n")
cat("  Input    :", input_path, "\n")
cat(strrep("-", 55), "\n\n")

confirm <- toupper(trimws(readline("Confirm? [Y/N]: ")))
while (!confirm %in% c("Y", "N")) {
  confirm <- toupper(trimws(readline("Confirm? [Y/N]: ")))
}
if (confirm == "N") stop("Execution cancelled by user.")

cat("\nStarting...\n\n")


# ==============================================================================
# 1. LOAD DATA
# ==============================================================================

df <- read_csv(
  input_path,
  col_types = cols(
    tweet_id        = col_character(),
    seed_tweet_id   = col_character(),
    parent_tweet_id = col_character(),
    .default        = col_guess()
  ),
  show_col_types = FALSE
)

cat("Corpus loaded:", nrow(df), "tweets\n\n")


# ==============================================================================
# 2. LEVEL 1 — TWEET VARIABLES
# ==============================================================================

parents_table <- df %>%
  filter(!is.na(parent_tweet_id), parent_tweet_id != "") %>%
  count(parent_tweet_id, name = "n_hijos_raw")

thread_pairs <- df %>%
  filter(
    !is.na(usuario_handle),
    !is.na(usuario_responde_a),
    usuario_responde_a != "NA",
    usuario_responde_a != "",
    usuario_handle != usuario_responde_a
  ) %>%
  transmute(key = paste(usuario_handle, usuario_responde_a, sep = "|||")) %>%
  pull(key)

data_tweet <- df %>%
  mutate(V = as.numeric(n_likes) + as.numeric(n_retuits)) %>%
  left_join(parents_table, by = c("tweet_id" = "parent_tweet_id")) %>%
  mutate(
    n_hijos    = replace(n_hijos_raw, is.na(n_hijos_raw), 0L),
    tiene_hijo = as.integer(n_hijos > 0L),
    r_i        = as.integer(
      !is.na(usuario_responde_a)           &
        usuario_responde_a != "NA"           &
        usuario_responde_a != ""             &
        usuario_handle != usuario_responde_a &
        paste(usuario_responde_a, usuario_handle, sep = "|||") %in% thread_pairs
    )
  ) %>%
  rename(Ni = nivel) %>%
  select(tweet_id, Ni, V, tiene_hijo, n_hijos, r_i)

write_csv(data_tweet, paste0("data_tweet_", party, ".csv"))
cat("OK data_tweet_", party, ".csv — ", nrow(data_tweet), " rows\n", sep = "")


# ==============================================================================
# 3. LEVEL 2 — THREAD VARIABLES
# ==============================================================================

seed_id_corpus <- df %>%
  filter(tipo_interaccion == "seed") %>%
  pull(seed_tweet_id) %>%
  unique() %>%
  first()

if (!is.na(seed_id_corpus) && seed_id_corpus != seed_id) {
  cat("WARNING: seed ID entered (", seed_id, ") differs from corpus (", seed_id_corpus,
      "). Using corpus value.\n\n", sep = "")
  seed_id <- seed_id_corpus
}

N_tweets        <- nrow(df)
n_participants  <- n_distinct(df$usuario_handle)
Pmax            <- max(df$nivel, na.rm = TRUE)
Pmed            <- round(mean(df$nivel[df$nivel > 0], na.rm = TRUE), 3)
R               <- round(mean(data_tweet$r_i[df$tipo_interaccion == "respuesta"],
                              na.rm = TRUE), 3)
Co              <- round(mean(data_tweet$tiene_hijo, na.rm = TRUE), 3)
HHI             <- df %>%
  filter(!is.na(usuario_handle)) %>%
  count(usuario_handle, name = "n_u") %>%
  mutate(s = n_u / N_tweets) %>%
  summarise(HHI = round(sum(s^2), 4)) %>%
  pull(HHI)

data_hilo <- tibble(
  actor           = seed_user,
  partido         = party,
  seed_tweet_id   = seed_id,
  N_tweets        = N_tweets,
  n_participantes = n_participants,
  Pmax            = Pmax,
  Pmed            = Pmed,
  R               = R,
  Co              = Co,
  HHI             = HHI
)

write_csv(data_hilo, paste0("data_hilo_", party, ".csv"))
cat("OK data_hilo_", party, ".csv — 1 row\n\n", sep = "")

cat(strrep("=", 55), "\n")
cat("VERIFICATION data_hilo_", party, ".csv\n", sep = "")
cat(strrep("=", 55), "\n")
for (col in names(data_hilo)) cat(sprintf("%-20s: %s\n", col, data_hilo[[col]]))
cat(strrep("=", 55), "\n\n")


# ==============================================================================
# 4. GRAPH B — USER INTERACTION NETWORK
# ==============================================================================
# Directed binary graph. Filters:
#   - Only tipo_interaccion == "respuesta"
#   - Seed node excluded (pure sink)
#   - Self-loops excluded
#   - Binarised: distinct(from, to) — one edge per directed pair

edges_B <- df %>%
  filter(
    tipo_interaccion    == "respuesta",
    !is.na(usuario_handle),     usuario_handle     != "",
    !is.na(usuario_responde_a), usuario_responde_a != "",
    usuario_handle      != seed_user,
    usuario_responde_a  != seed_user,
    usuario_handle      != usuario_responde_a
  ) %>%
  select(from = usuario_handle, to = usuario_responde_a) %>%
  distinct(from, to)

# Full graph B (including cloud nodes connected only to/from seed)
all_nodes <- union(edges_B$from, edges_B$to)

full_graph <- graph_from_data_frame(
  d        = edges_B,
  vertices = data.frame(name = all_nodes),
  directed = TRUE
)

# Cloud nodes: only connected to/from seed in the full corpus
cloud_nodes <- df %>%
  filter(
    tipo_interaccion    == "respuesta",
    !is.na(usuario_handle),
    !is.na(usuario_responde_a),
    usuario_handle      != seed_user,
    usuario_responde_a  != seed_user,
    usuario_handle      != usuario_responde_a
  ) %>%
  {
    nodes_in_B <- union(.$from, .$to)
    setdiff(
      df %>%
        filter(tipo_interaccion == "respuesta") %>%
        pull(usuario_handle) %>%
        unique(),
      nodes_in_B
    )
  }

# Louvain graph: exclude seed and cloud nodes
louvain_nodes <- setdiff(V(full_graph)$name, c(seed_user, cloud_nodes))
louvain_graph <- induced_subgraph(full_graph,
                                   vids = which(V(full_graph)$name %in% louvain_nodes))

cat("Graph B:", vcount(full_graph), "nodes,", ecount(full_graph), "edges\n")
cat("  Cloud nodes (comunidad_id=0):", length(cloud_nodes), "\n")
cat("  Louvain subgraph:", vcount(louvain_graph), "nodes\n\n")


# ==============================================================================
# 5. COMMUNITY DETECTION — Louvain
# ==============================================================================

louvain_undir <- as.undirected(louvain_graph, mode = "collapse")
communities   <- cluster_louvain(louvain_undir)
mem_louvain   <- setNames(as.integer(membership(communities)),
                           V(louvain_graph)$name)

n_communities <- length(unique(mem_louvain))
cat("Communities detected:", n_communities, "\n")
cat("Modularity Q:        ", round(modularity(communities), 4), "\n\n")

# Assign comunidad_id = 0 to seed and cloud nodes in full graph
mem_full <- setNames(rep(0L, vcount(full_graph)), V(full_graph)$name)
mem_full[names(mem_louvain)] <- mem_louvain
V(full_graph)$comunidad_id <- mem_full[V(full_graph)$name]

node_names_lou <- V(louvain_graph)$name
mem_vec        <- setNames(as.integer(membership(communities)), node_names_lou)


# ==============================================================================
# 6. LEVEL 3 — COMMUNITY VARIABLES
# ==============================================================================

btw_global <- betweenness(full_graph, directed = TRUE, normalized = TRUE)

# Inter-community betweenness (custom implementation)
inter_community_btw <- function(g, mem) {
  n       <- vcount(g)
  adj_out <- lapply(seq_len(n), function(v) as.integer(neighbors(g, v, mode = "out")))
  btw     <- numeric(n)
  q_arr   <- integer(n)
  stk_arr <- integer(n)

  for (s in seq_len(n)) {
    sigma  <- numeric(n);      sigma[s] <- 1
    dist_v <- integer(n) - 1L; dist_v[s] <- 0L
    pred   <- vector("list", n)
    qh <- 1L; qt <- 1L; q_arr[1] <- s; sp <- 0L

    while (qh <= qt) {
      v  <- q_arr[qh]; qh <- qh + 1L
      sp <- sp + 1L; stk_arr[sp] <- v
      for (w in adj_out[[v]]) {
        if (dist_v[w] < 0L) {
          qt <- qt + 1L; q_arr[qt] <- w; dist_v[w] <- dist_v[v] + 1L
        }
        if (dist_v[w] == dist_v[v] + 1L) {
          sigma[w] <- sigma[w] + sigma[v]
          pred[[w]] <- c(pred[[w]], v)
        }
      }
    }

    delta <- numeric(n)
    while (sp > 0L) {
      w  <- stk_arr[sp]; sp <- sp - 1L
      if (w == s) next
      coef <- (if (mem[w] != mem[s]) 1 else 0) + delta[w]
      for (v in pred[[w]]) delta[v] <- delta[v] + sigma[v] / sigma[w] * coef
      btw[w] <- btw[w] + delta[w]
    }
  }

  n_inter <- sum(outer(mem, mem, "!="))
  if (n_inter > 0) btw <- btw / n_inter
  setNames(btw, V(g)$name)
}

cat("Computing inter-community betweenness...\n")
btw_inter <- inter_community_btw(louvain_graph, mem_vec)

mean_bi   <- mean(btw_inter)
above_avg <- sort(btw_inter[btw_inter > mean_bi], decreasing = TRUE)
Ab_int_val <- if (length(above_avg) > 0) {
  h <- head(names(above_avg), 9)
  h <- ifelse(startsWith(h, "@"), h, paste0("@", h))
  paste(h, collapse = " ; ")
} else NA_character_

edge_mat_lou <- get.edgelist(louvain_graph, names = TRUE)
edges_lou    <- tibble(
  from     = edge_mat_lou[, 1],
  to       = edge_mat_lou[, 2],
  com_from = mem_vec[from],
  com_to   = mem_vec[to]
)

nodes_with_inter <- union(
  edges_lou$from[edges_lou$com_from != edges_lou$com_to],
  edges_lou$to  [edges_lou$com_from != edges_lou$com_to]
)

Po_int_tbl <- tibble(usuario = node_names_lou, com_id = mem_vec) %>%
  group_by(com_id) %>%
  summarise(
    T_com  = n(),
    Po_int = round(sum(usuario %in% nodes_with_inter) / n(), 3),
    .groups = "drop"
  )

coms_ge3   <- Po_int_tbl$com_id[Po_int_tbl$T_com >= 3]
Fr_int_val <- round(
  mean(Po_int_tbl$Po_int[Po_int_tbl$com_id %in% coms_ge3] == 0), 3
)

compute_community_vars <- function(cid) {
  members <- node_names_lou[mem_vec == cid]
  idx     <- which(V(louvain_graph)$name %in% members)
  sub     <- induced_subgraph(louvain_graph, vids = idx)
  n <- vcount(sub); m <- ecount(sub)
  gin   <- degree(sub, mode = "in")
  gout  <- degree(sub, mode = "out")
  btw_s <- betweenness(sub, directed = TRUE, normalized = TRUE)
  top_cg <- sort(names(gin [gin  == max(gin )]))[1]
  top_cb <- sort(names(btw_s[btw_s == max(btw_s)]))[1]
  tibble(
    comunidad_id     = cid,
    T                = n,
    D                = if (n > 1) round(m / (n * (n - 1)), 4) else NA_real_,
    Cg_entrada_media = round(mean(gin), 3),
    Cg_salida_media  = round(mean(gout), 3),
    Cg_nodo_top      = top_cg,
    Cg_top_entrada   = as.integer(gin[top_cg]),
    Cc               = if (mean(gin) > 0) round(max(gin) / mean(gin), 3) else NA_real_,
    Cb_media         = round(mean(btw_s), 4),
    Cb_nodo_top      = top_cb,
    Cb_top_valor     = round(btw_s[top_cb], 4)
  )
}

com_vars_df <- bind_rows(lapply(sort(unique(mem_vec)), compute_community_vars))

data_comunidad <- com_vars_df %>%
  filter(T >= 3) %>%
  left_join(select(Po_int_tbl, com_id, Po_int),
            by = c("comunidad_id" = "com_id")) %>%
  mutate(Fr_int = Fr_int_val, Ab_int = Ab_int_val) %>%
  arrange(desc(T)) %>%
  select(comunidad_id, T, D, Cg_entrada_media, Cg_salida_media,
         Cg_nodo_top, Cg_top_entrada, Cc, Cb_media, Cb_nodo_top,
         Cb_top_valor, Po_int, Fr_int, Ab_int)

write_csv(data_comunidad, paste0("data_comunidad_", party, ".csv"))
cat("OK data_comunidad_", party, ".csv — ",
    nrow(data_comunidad), " communities (T>=3)\n", sep = "")


# ==============================================================================
# 7. GRAPH NODE AND EDGE EXPORTS
# ==============================================================================

grafo_nodos <- tibble(
  usuario_handle = V(full_graph)$name,
  comunidad_id   = as.integer(mem_full[V(full_graph)$name]),
  degree_in      = as.integer(degree(full_graph, mode = "in")),
  degree_out     = as.integer(degree(full_graph, mode = "out")),
  degree_total   = as.integer(degree(full_graph, mode = "total")),
  betweenness    = round(btw_global[V(full_graph)$name], 6),
  tipo_nodo      = case_when(
    usuario_handle == seed_user           ~ "seed",
    usuario_handle %in% cloud_nodes      ~ "cloud",
    TRUE                                  ~ "community"
  )
)

edge_mat_full <- get.edgelist(full_graph, names = TRUE)
grafo_aristas <- tibble(
  from           = edge_mat_full[, 1],
  to             = edge_mat_full[, 2],
  comunidad_from = as.integer(mem_full[from]),
  comunidad_to   = as.integer(mem_full[to]),
  tipo           = case_when(
    from == seed_user | to == seed_user ~ "seed",
    comunidad_from == comunidad_to      ~ "internal",
    TRUE                                ~ "cross"
  )
)

write_csv(grafo_nodos,   paste0("grafo_nodos_",   party, ".csv"))
write_csv(grafo_aristas, paste0("grafo_aristas_", party, ".csv"))
cat("OK grafo_nodos_",   party, ".csv — ", nrow(grafo_nodos),   " nodes\n", sep = "")
cat("OK grafo_aristas_", party, ".csv — ", nrow(grafo_aristas), " edges\n\n", sep = "")


# ==============================================================================
# 8. SUMMARY
# ==============================================================================

cat(strrep("=", 60), "\n")
cat("SUMMARY LEVEL 3 —", party, "\n")
cat(strrep("=", 60), "\n")
cat("Graph B nodes (full):       ", vcount(full_graph),    "\n")
cat("  → Seed:                   ", 1,                     "\n")
cat("  → Cloud (comunidad_id=0): ", length(cloud_nodes),   "\n")
cat("  → In Louvain subgraph:    ", vcount(louvain_graph), "\n")
cat("Graph B edges (full):       ", ecount(full_graph),    "\n")
cat("Total communities (Louvain):", n_communities,         "\n")
cat("Communities in output (T>=3):", nrow(data_comunidad), "\n")
cat("Modularity Q:               ", round(modularity(communities), 4), "\n")
cat(strrep("=", 60), "\n\n")
print(as.data.frame(data_comunidad))
