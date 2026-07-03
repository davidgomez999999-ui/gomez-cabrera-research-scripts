# ==============================================================================
# 04_iqd_sample_space.R
# ==============================================================================
# Generates the normative sample space of the IQD (Discursive Quality Index).
# Produces all 256 binary combinations (2^8) of the eight IQD indicator
# variables, computes the three normalised dimensions and the final IQD score
# for each combination, and exports the result as a reference matrix.
#
# This file serves as the theoretical reference dictionary: any LLM-coded
# tweet result is matched against this matrix via ID_Binario (foreign key)
# to retrieve its IQD score.
#
# Output:  Matriz_Maestra_IQD_Final.csv
#          (256-row reference matrix; placed in the working directory)
#
# IQD dimensions and indicators:
#   Argumentative (Arg): Ji (justification), Ci (content), Rmi (reframing)
#   Relational    (Rel): Mai (mutual acknowledgement), Pei (personal attack)
#   Epistemic     (Epi): Afi (affirmation), Eai (emotional appeal), Vci (vagueness)
#
# Normalisation ranges:
#   Arg_norm: [(Ji + Ci - Rmi) - (-1)] / [2 - (-1)]
#   Rel_norm: [(Mai - Pei) - (-1)]     / [1 - (-1)]
#   Epi_norm: [(Afi - Eai - Vci) - (-2)] / [1 - (-2)]
#   IQD_Final: mean(Arg_norm, Rel_norm, Epi_norm)
#
# Dependencies: ggplot2
#
# Version: 1.0 — as used in the Bachelor's Thesis (2026)
# Author:  David Gómez Cabrera (2026)
# License: MIT — https://opensource.org/licenses/MIT
# ==============================================================================

if (!require(ggplot2)) install.packages("ggplot2")
library(ggplot2)


# ==============================================================================
# 1. GENERATE SAMPLE SPACE (deterministic — temperature 0)
# ==============================================================================

variables <- c("Ji", "Ci", "Rmi", "Mai", "Pei", "Afi", "Eai", "Vci")
df_iqd    <- expand.grid(replicate(length(variables), c(0, 1), simplify = FALSE))
colnames(df_iqd) <- variables


# ==============================================================================
# 2. COMPUTE DIMENSIONS
# ==============================================================================

df_iqd$Arg_norm <- ((df_iqd$Ji + df_iqd$Ci - df_iqd$Rmi) - (-1)) / (2 - (-1))
df_iqd$Rel_norm <- ((df_iqd$Mai - df_iqd$Pei) - (-1))             / (1 - (-1))
df_iqd$Epi_norm <- ((df_iqd$Afi - df_iqd$Eai - df_iqd$Vci) - (-2)) / (1 - (-2))

df_iqd$IQD_Final <- (df_iqd$Arg_norm + df_iqd$Rel_norm + df_iqd$Epi_norm) / 3

# Binary ID: unique identifier for matching with coded tweet results (foreign key)
df_iqd$ID_Binario <- apply(df_iqd[, 1:8], 1, paste, collapse = "")


# ==============================================================================
# 3. VISUALISATION — Theoretical probability distribution
# ==============================================================================

plot_iqd <- ggplot(df_iqd, aes(x = IQD_Final, fill = ..x..)) +
  geom_histogram(binwidth = 0.02, color = "white", linewidth = 0.1) +
  scale_fill_gradientn(colors = c("#e74c3c", "#f1c40f", "#27ae60")) +
  geom_vline(aes(xintercept = 0.5),
             linetype = "dashed", color = "black", linewidth = 0.8) +
  annotate("text", x = 0.15, y = 15,
           label = "DELIBERATIVE DEFICIT",
           color = "#e74c3c", fontface = "bold", size = 3) +
  annotate("text", x = 0.85, y = 15,
           label = "EXCELLENCE",
           color = "#27ae60", fontface = "bold", size = 3) +
  labs(
    title    = "Theoretical Probability Distribution of the IQD",
    subtitle = "Normative reference — full sample space (n = 256)",
    x        = "Discursive Quality (Final Score)",
    y        = "Frequency of Combinations",
    caption  = "Dashed line: theoretical mean (0.5)"
  ) +
  scale_x_continuous(breaks = seq(0, 1, 0.1)) +
  theme_minimal() +
  theme(legend.position = "none", panel.grid.minor = element_blank())

print(plot_iqd)


# ==============================================================================
# 4. EXPORT
# ==============================================================================

tryCatch({
  write.csv(df_iqd, "Matriz_Maestra_IQD_Final.csv", row.names = FALSE)
  cat("✓ Exported: Matriz_Maestra_IQD_Final.csv\n")
}, error = function(e) {
  cat("ERROR: Could not save file. Check that the working directory is writable.\n")
})


# ==============================================================================
# METHODOLOGICAL NOTES
# ==============================================================================
# 1. FILE FUNCTION: This CSV is the reference dictionary. Any LLM output is
#    matched against this mapping via ID_Binario to retrieve the IQD score.
# 2. STATISTICAL INTERPRETATION: The bell-shaped histogram confirms that the
#    index has a balanced theoretical normal distribution.
# 3. DATA MATCHING: In the next phase, ID_Binario is used to join against
#    the coded tweet dataset.
# ==============================================================================
