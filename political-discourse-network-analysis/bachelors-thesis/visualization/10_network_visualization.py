"""
10_network_visualization.py
===========================
Generates final network visualisation images for each political ecosystem
and for the global discursive ecosystem, overlaying KDE community blobs
on Gephi-exported PNG network graphs.

For each ecosystem (PSOE, PP, VOX, PODEMOS), the script:
  1. Reads node coordinates and community membership from the GEXF file.
  2. Loads the corresponding PNG network export from Gephi.
  3. Removes black backgrounds if present (non-transparent Gephi exports).
  4. Draws KDE-based community blobs (contourf) calibrated to node positions.
  5. Overlays the network graph on a black canvas with an actor label.
  6. Saves the final image at 180 DPI.

For the global ecosystem (generar_viz8), community blobs are coloured by
political identity (PSOE, PP, VOX, PODEMOS) rather than community index.

Input files (must be in the working directory):
  grafo_PSOE.gexf,    grafo_PSOE.png
  grafo_PP.gexf,      grafo_PP.png
  grafo_VOX.gexf,     grafo_VOX.png
  grafo_PODEMOS.gexf, grafo_PODEMOS.png
  grafo_GLOBAL.gexf,  grafo_GLOBAL.png

Output files:
  viz_PSOE_final.png
  viz_PP_final.png
  viz_VOX_final.png
  viz_PODEMOS_final.png
  viz_GLOBAL_final.png

Known limitations (v1.0):
  - GEXF coordinate calibration assumes a linear mapping between Gephi's
    coordinate space and PNG pixel space. Non-linear layouts may produce
    blob misalignment.
  - KDE bandwidth (bw=0.60) was tuned manually for this dataset.
    Different network sizes may require adjustment.

Dependencies:
  xml.etree.ElementTree (stdlib), pandas, numpy, Pillow, matplotlib,
  scipy

Version: 1.0 — as used in the Bachelor's Thesis (2026)
Author:  David Gómez Cabrera (2026)
License: MIT — https://opensource.org/licenses/MIT
"""

import xml.etree.ElementTree as ET
import numpy as np
import warnings
import pandas as pd
from PIL import Image
import matplotlib.pyplot as plt
from scipy.stats import gaussian_kde

warnings.filterwarnings("ignore")

# ==============================================================================
# CONFIGURATION
# ==============================================================================

ECOSYSTEMS = [
    {
        "gexf":        "grafo_PSOE.gexf",
        "png":         "grafo_PSOE.png",
        "output":      "viz_PSOE_final.png",
        "margin":      500,
        "actor_color": "#C8675F",
        "actor_label": "PSOE",
        "global":      False,
    },
    {
        "gexf":        "grafo_PP.gexf",
        "png":         "grafo_PP.png",
        "output":      "viz_PP_final.png",
        "margin":      500,
        "actor_color": "#5B8DB8",
        "actor_label": "PP",
        "global":      False,
    },
    {
        "gexf":        "grafo_VOX.gexf",
        "png":         "grafo_VOX.png",
        "output":      "viz_VOX_final.png",
        "margin":      800,
        "actor_color": "#7AAF77",
        "actor_label": "VOX",
        "global":      False,
    },
    {
        "gexf":        "grafo_PODEMOS.gexf",
        "png":         "grafo_PODEMOS.png",
        "output":      "viz_PODEMOS_final.png",
        "margin":      500,
        "actor_color": "#9575A8",
        "actor_label": "PODEMOS",
        "global":      False,
    },
    {
        "gexf":        "grafo_GLOBAL.gexf",
        "png":         "grafo_GLOBAL.png",
        "output":      "viz_GLOBAL_final.png",
        "margin":      500,
        "actor_color": "white",
        "actor_label": "Global discursive ecosystem",
        "global":      True,
    },
]

BLOB_PALETTE = [
    "#8FB4CC", "#B4A0C8", "#C8A8A8", "#A0C4B4",
    "#C8C0A0", "#A0B4C8", "#C4B0C0", "#B4C8A0",
    "#C8B8A0", "#A4C0C8", "#C0A4B8", "#B8C8A8",
]

POLITICAL_COLORS = {
    "PSOE":    "#C8675F",
    "PP":      "#5B8DB8",
    "VOX":     "#7AAF77",
    "PODEMOS": "#9575A8",
}


# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

def extract_nodes(gexf_path: str) -> pd.DataFrame:
    """Parse node positions and attributes from a GEXF file."""
    tree  = ET.parse(gexf_path)
    root  = tree.getroot()
    ns_g  = "http://gexf.net/1.3"
    ns_viz = "http://gexf.net/1.3/viz"
    attrs = {
        a.get("id"): a.get("title")
        for a in root.findall(f".//{{{ns_g}}}attribute")
    }
    nodes = []
    for node in root.findall(f".//{{{ns_g}}}node"):
        nid = node.get("id")
        pos = node.find(f"{{{ns_viz}}}position")
        x   = float(pos.get("x")) if pos is not None else 0.0
        y   = float(pos.get("y")) if pos is not None else 0.0
        attvalues = {
            attrs.get(av.get("for"), av.get("for")): av.get("value")
            for av in node.findall(f".//{{{ns_g}}}attvalue")
        }
        nodes.append({"Id": nid, "x": x, "y": y, **attvalues})
    return pd.DataFrame(nodes)


def remove_black_background(img: Image.Image, threshold_ratio: float = 0.3) -> Image.Image:
    """Remove solid black backgrounds from Gephi PNG exports."""
    arr = np.array(img.convert("RGBA")).copy()
    r, g, b, a = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2], arr[:, :, 3]
    black_mask = (r.astype(int) + g.astype(int) + b.astype(int) < 20) & (a > 200)
    h, w = arr.shape[:2]
    if black_mask.sum() > (w * h * threshold_ratio):
        print("  Black background detected — removing...")
        arr[black_mask, 3] = 0
        return Image.fromarray(arr, "RGBA")
    print("  Transparent PNG — OK")
    return img.convert("RGBA")


def calibrate_coordinates(df: pd.DataFrame, img: Image.Image, margin: int):
    """
    Map Gephi coordinate space to PNG pixel space using visible pixel bounds.
    Returns (scale, offset_x, offset_y) for the linear transformation.
    """
    arr2 = np.array(img)
    r2, g2, b2, a2 = arr2[:, :, 0], arr2[:, :, 1], arr2[:, :, 2], arr2[:, :, 3]
    vis = (r2.astype(int) + g2.astype(int) + b2.astype(int) > 30) & (a2 > 50)
    vy, vx = np.where(vis)
    png_x_min = float(vx.min()) + margin
    png_x_max = float(vx.max()) + margin
    png_y_max = float(vy.max()) + margin

    gx_min, gx_max = df["x"].min(), df["x"].max()
    gy_min, gy_max = df["y"].min(), df["y"].max()
    scale = (
        (png_x_max - png_x_min) / (gx_max - gx_min)
        + (float(vy.min() + margin) - png_y_max) / (gy_min - gy_max)  # corrected sign
    ) / 2
    # Simplified: use average of x and y scale
    sx = (png_x_max - png_x_min) / (gx_max - gx_min) if gx_max != gx_min else 1.0
    sy = (float(vy.max() - vy.min())) / (gy_max - gy_min) if gy_max != gy_min else 1.0
    scale = (sx + sy) / 2
    ox = png_x_min - gx_min * scale
    oy = png_y_max + gy_min * scale
    return scale, ox, oy


def gephi_to_px(gx, gy, scale, ox, oy):
    return gx * scale + ox, -gy * scale + oy


def draw_blob(ax, xs, ys, color, alpha=0.18, bw=0.60, zorder=2):
    """Draw a KDE-based community blob as a filled contour."""
    if len(xs) < 3:
        return
    dx = max(np.ptp(xs), 1.0)
    dy = max(np.ptp(ys), 1.0)
    pad = max(dx, dy) * 0.70
    x0, x1 = np.min(xs) - pad, np.max(xs) + pad
    y0, y1 = np.min(ys) - pad, np.max(ys) + pad
    gx_grid, gy_grid = np.mgrid[x0:x1:140j, y0:y1:140j]
    try:
        kde = gaussian_kde(np.vstack([xs, ys]), bw_method=bw)
        z   = kde(np.vstack([gx_grid.ravel(), gy_grid.ravel()])).reshape(140, 140)
        ax.contourf(gx_grid, gy_grid, z,
                    levels=[z.max() * 0.025, z.max()],
                    colors=[color], alpha=alpha, zorder=zorder)
    except Exception:
        pass


def get_global_blob_color(com_id: str) -> str:
    """Return political identity colour for global ecosystem blobs."""
    s = str(com_id)
    for party, color in POLITICAL_COLORS.items():
        if party in s:
            return color
    return "#888888"


# ==============================================================================
# MAIN RENDERING LOOP
# ==============================================================================

for eco in ECOSYSTEMS:
    print(f"\n{'='*60}")
    print(f"Processing: {eco['actor_label']}")
    print(f"{'='*60}")

    margin = eco["margin"]

    # Load and parse GEXF
    df = extract_nodes(eco["gexf"])
    df["x"] = df["x"].astype(float)
    df["y"] = df["y"].astype(float)

    # Load PNG and remove background
    img_orig = Image.open(eco["png"]).convert("RGBA")
    img_orig = remove_black_background(img_orig)
    img_w, img_h = img_orig.size

    # Build canvas
    canvas_w = img_w + 2 * margin
    canvas_h = img_h + 2 * margin
    canvas_bg = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 255))

    # Calibrate coordinates
    scale, ox, oy = calibrate_coordinates(df, img_orig, margin)
    df["px"] = df.apply(lambda r: gephi_to_px(r["x"], r["y"], scale, ox, oy)[0], axis=1)
    df["py"] = df.apply(lambda r: gephi_to_px(r["x"], r["y"], scale, ox, oy)[1], axis=1)
    print(f"  Calibration OK | px: {df.px.min():.0f}–{df.px.max():.0f}")

    # Build figure
    fig, ax = plt.subplots(
        figsize=(canvas_w / 180, canvas_h / 180), facecolor="black"
    )
    fig.subplots_adjust(0, 0, 1, 1)
    ax.set_xlim(0, canvas_w)
    ax.set_ylim(canvas_h, 0)
    ax.set_facecolor("black")
    ax.axis("off")

    # Layer 1 — black background
    ax.imshow(np.array(canvas_bg),
              extent=[0, canvas_w, canvas_h, 0], aspect="auto", zorder=1)

    # Layer 2 — community blobs
    if eco["global"]:
        # Global: blob per ecosystem cloud + per community
        for party in ["PSOE", "PP", "VOX", "PODEMOS"]:
            cloud = df[df["comunidad_id"] == f"{party}_0"]
            if len(cloud) >= 3:
                draw_blob(ax, cloud["px"].values, cloud["py"].values,
                          get_global_blob_color(f"{party}_0"),
                          alpha=0.15, bw=0.45, zorder=2)
        com_ids = [
            c for c in df["comunidad_id"].unique()
            if c and str(c) != "nan" and not str(c).endswith("_0")
        ]
        for cid in com_ids:
            members = df[df["comunidad_id"] == cid]
            if len(members) < 3:
                continue
            draw_blob(ax, members["px"].values, members["py"].values,
                      get_global_blob_color(cid), alpha=0.18, bw=0.55, zorder=2)

        # Legend
        for lbl, col in POLITICAL_COLORS.items():
            ax.scatter([], [], s=280, c=[col], label=lbl, linewidths=0)
        leg = ax.legend(
            loc="lower left", fontsize=36, frameon=True,
            labelcolor="white", markerscale=3.0,
            bbox_to_anchor=(0.03, 0.06),
            handletextpad=0.8, labelspacing=0.7,
        )
        for t in leg.get_texts():
            t.set_alpha(0.80)
        leg.get_frame().set_facecolor("white")
        leg.get_frame().set_alpha(0.08)
        leg.get_frame().set_edgecolor("white")
        leg.get_frame().set_linewidth(0.5)
    else:
        # Individual ecosystem: blob per community
        com_ids = sorted([
            c for c in df["comunidad_id"].unique()
            if c and str(c) != "nan"
        ])
        blob_color = {
            cid: BLOB_PALETTE[i % len(BLOB_PALETTE)]
            for i, cid in enumerate(com_ids)
        }
        for cid in com_ids:
            members = df[df["comunidad_id"] == cid]
            if len(members) < 3:
                continue
            draw_blob(ax, members["px"].values, members["py"].values,
                      blob_color[cid], zorder=2)

    # Layer 3 — network graph overlay
    canvas_top = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    canvas_top.paste(img_orig, (margin, margin), img_orig)
    ax.imshow(np.array(canvas_top),
              extent=[0, canvas_w, canvas_h, 0], aspect="auto", zorder=3)

    # Actor label
    fontsize = 48 if eco["global"] else 32
    ax.text(0.04, 0.96, eco["actor_label"],
            transform=ax.transAxes,
            fontsize=fontsize, fontweight="bold",
            color=eco["actor_color"], alpha=0.92,
            fontfamily="sans-serif", va="bottom")

    plt.savefig(eco["output"], dpi=180, bbox_inches="tight",
                facecolor="black", pad_inches=0)
    plt.close()
    print(f"  Saved: {eco['output']}")

print("\n✓ All visualisations complete.")
