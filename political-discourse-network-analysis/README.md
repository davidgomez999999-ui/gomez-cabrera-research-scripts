# Political Discourse and Network Analysis on X

Structural and network analysis of political discourse in Spanish Twitter/X
ecosystems, developed as part of a research program on algorithmic architecture
and discursive capacity in digital platforms.

This project supports two publications:

- **Bachelor's Thesis** — *Indicios sobre la Capacidad Discursiva de X: Un
  análisis multinivel del debate político español desde la Machine Anthropology*,
  David Gómez Cabrera, Universidad de Granada, 2026.
  Available at: https://doi.org/10.5281/zenodo.21138746

- **Commentary** — *Inscription Bias and Discursive Capacity on X*,
  David Gómez Cabrera (under review).

---

## Research context

The study analyses four Spanish political ecosystems on X (PSOE, PP, VOX,
Podemos) using a multi-level framework that combines structural network analysis
with a custom Discursive Quality Index (IQD). The central argument is that X's
interface inscribes a structural asymmetry: agreement can be expressed silently
(like, repost) while disagreement requires text production, introducing a
platform-level bias into any corpus extracted from the platform.

Corpus: 2,928 tweets across four reply threads (one seed tweet per ecosystem).
Data collection: January 2026.

---

## Pipeline

The scripts in this project implement the following analytical pipeline:

```
01_extract_corpus.py          — semi-manual hierarchical corpus extraction
        ↓
02_clean_data.R               — deduplication, scale correction, level reconstruction
03_build_corpus.R             — merge four party corpora into unified dataset
        ↓
04_iqd_sample_space.R         — generate IQD normative reference matrix (n=256)
05_stratified_sampling.R      — draw calibration and validation samples
        ↓
06_structural_variables.R     — tweet, thread, and community variables (Levels 1–3)
07_global_ecosystem_variables.R — cross-ecosystem variables (Level 4)
        ↓
08_node_centrality.R          — rank community nodes for IQD coding selection
09_extract_top_node_tweets.R  — extract highest-engagement tweet per top node
        ↓
10_network_visualization.py   — generate final network visualisations with community blobs
        ↓
11_endorsement_reply_ratio.R  — compute endorsement-to-reply ratio (Commentary)
```

Scripts 01–10 support the Bachelor's Thesis.
Script 11 supports the Commentary.

---

## Repository structure

```
political-discourse-network-analysis/
├── README.md
├── bachelors-thesis/
│   ├── extraction/
│   │   └── 01_extract_corpus.py
│   ├── cleaning/
│   │   ├── 02_clean_data.R
│   │   └── 03_build_corpus.R
│   ├── structural-analysis/
│   │   ├── 04_iqd_sample_space.R
│   │   ├── 05_stratified_sampling.R
│   │   ├── 06_structural_variables.R
│   │   └── 07_global_ecosystem_variables.R
│   ├── network-analysis/
│   │   ├── 08_node_centrality.R
│   │   └── 09_extract_top_node_tweets.R
│   └── visualization/
│       └── 10_network_visualization.py
└── commentary/
    └── 11_endorsement_reply_ratio.R
```

---

## Data

Raw and cleaned corpus data are not included in this repository due to
user privacy constraints (Twitter/X Terms of Service).

The anonymised corpus and methodological walkthrough are deposited at Zenodo:

- Corpus and results: https://doi.org/10.5281/zenodo.21138746
- Methodological walkthrough: https://doi.org/10.5281/zenodo.21138832

---

## Reproducibility

Randomisation seeds are fixed and documented for exact replication:

| Script                      | Seed | Purpose                        |
|-----------------------------|------|--------------------------------|
| 05_stratified_sampling.R    | 8301 | Calibration sample             |
| 05_stratified_sampling.R    | 8302 | Validation sample              |
| 06_structural_variables.R   | 2026 | Louvain community detection    |

---

## Dependencies

**R packages:** tidyverse, dplyr, readr, purrr, igraph, ggplot2

**Python packages:** pandas, numpy, Pillow, matplotlib, scipy, selenium,
undetected-chromedriver, webdriver-manager

---

## Citation

If you use these scripts, please cite:

> Gómez Cabrera, D. (2026). *gomez-cabrera-research-scripts* [Software].
> GitHub. https://github.com/davidgomez999999-ui/gomez-cabrera-research-scripts

If using scripts that support the Bachelor's Thesis, also cite:

> Gómez Cabrera, D. (2026). *Indicios sobre la Capacidad Discursiva de X:
> Un análisis multinivel del debate político español desde la Machine
> Anthropology* [Bachelor's Thesis, Universidad de Granada].
> Zenodo. https://doi.org/10.5281/zenodo.21138746

---

## License

MIT License — see [LICENSE](../LICENSE)
