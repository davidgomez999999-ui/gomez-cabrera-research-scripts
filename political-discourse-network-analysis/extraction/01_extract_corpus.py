"""
01_extract_corpus.py
====================
Semi-manual hierarchical extractor for X (Twitter) reply threads.
Extracts tweet metadata, interaction metrics, and derived media variables,
and unifies all data into a single CSV file.

Extracted variables per tweet
------------------------------
- tweet_id, seed_tweet_id, parent_tweet_id
- usuario_responde_a, tipo_interaccion
- usuario_handle, texto_tweet
- n_respuestas, n_likes, n_retuits
- fecha_publicacion, enlace_tweet, fecha_extraccion
- nivel (hierarchical level: 0 = seed, n+1 = reply to level n)
- tiene_imagen, tiene_video (derived)

Known limitations (v1.0)
-------------------------
- Does not extract emoji characters (encoding not resolved at this version).
- Does not download image or video files; only flags their presence (tiene_imagen, tiene_video).
- Semi-manual operation: the user must scroll and trigger captures interactively.
- parent_tweet_id inference relies on DOM structure and may be imprecise
  in deeply nested threads or when X renders partial trees.

Version
-------
v1.0 — Instrument as used in the TFG corpus collection (January 2026).
       Limitations above are documented for transparency; improvements
       are planned for subsequent research phases.

Author
------
David Gómez Cabrera (2026)
MIT License — see LICENSE file or https://opensource.org/licenses/MIT

Citation
--------
If you use this script, please cite the associated repository and,
where applicable, the published work it supports.
"""

# ============================================================
# IMPORTS
# ============================================================

import re
import time
import json
from datetime import datetime
from typing import Dict, List

import pandas as pd
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

# ============================================================
# DRIVER SETUP
# ============================================================

from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from webdriver_manager.chrome import ChromeDriverManager

try:
    import undetected_chromedriver as uc
    USE_UC = True
    print("✓ Using undetected-chromedriver (bot detection bypass enabled)")
except ImportError:
    USE_UC = False
    print("⚠ undetected-chromedriver not available — falling back to standard Chrome")

# ============================================================
# CONFIGURATION
# ============================================================

OUTPUT_CSV_DEFAULT = "tweets.csv"

# ============================================================
# DRIVER INITIALISATION
# ============================================================

def init_driver():
    """Initialise and return a Selenium WebDriver instance."""
    if USE_UC:
        try:
            driver = uc.Chrome()
            driver.maximize_window()
            return driver
        except Exception as e:
            err = str(e)
            print(f"[WARN] undetected-chromedriver failed: {err}")
            m = re.search(r"Current browser version is (\d+)\.", err)
            if m:
                major = m.group(1)
                try:
                    print(f"[INFO] Retrying with version_main={major} to match installed Chrome.")
                    driver = uc.Chrome(version_main=int(major))
                    driver.maximize_window()
                    return driver
                except Exception as e2:
                    print(f"[WARN] Retry with version_main failed: {e2}")
            if "only supports Chrome version" in err:
                print("[WARN] Likely Chrome/driver version mismatch.")
                print("       Update Chrome or specify version_main in uc.Chrome().")
            print("[INFO] Falling back to standard Chrome...")

    options = webdriver.ChromeOptions()
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_experimental_option('excludeSwitches', ['enable-automation'])
    options.add_experimental_option('useAutomationExtension', False)
    service = Service(ChromeDriverManager().install())
    driver = webdriver.Chrome(service=service, options=options)
    driver.maximize_window()
    return driver

# ============================================================
# SAFE DOM HELPERS
# ============================================================

def safe_get_text(element, selector: str) -> str:
    try:
        return element.find_element(By.CSS_SELECTOR, selector).text.strip()
    except Exception:
        return ""


def safe_get_attribute(element, selector: str, attr: str) -> str:
    try:
        return element.find_element(By.CSS_SELECTOR, selector).get_attribute(attr)
    except Exception:
        return ""

# ============================================================
# URL PARSING HELPERS
# ============================================================

def extract_status_id_from_url(url: str) -> str:
    """Extract numeric tweet ID from a /status/{id} URL."""
    if not url or "/status/" not in url:
        return ""
    match = re.search(r"/status/(\d+)", url)
    return match.group(1) if match else ""


def extract_status_info_from_url(url: str):
    """Extract (username, status_id) from x.com/{user}/status/{id} URLs."""
    if not url:
        return "", ""
    match = re.search(r"x\.com/([^/]+)/status/(\d+)", url)
    if not match:
        return "", ""
    return match.group(1), match.group(2)


def extract_user_from_profile_url(url: str) -> str:
    """Extract username from an x.com/{user} profile URL."""
    if not url:
        return ""
    match = re.search(r"x\.com/([^/?#]+)", url)
    if not match:
        return ""
    user = match.group(1).strip()
    if not user or user in ["home", "explore", "i", "notifications", "messages", "search"]:
        return ""
    return user


def parse_count_from_label(label: str) -> str:
    """Parse interaction count (replies, likes, reposts) from an aria-label string."""
    if not label:
        return ""
    text = label.lower().replace("\xa0", " ").strip()
    match = re.search(r"(\d+(?:[\.,]\d+)?)", text)
    if not match:
        return ""
    raw_number = match.group(1).replace(",", ".")
    try:
        value = float(raw_number)
    except ValueError:
        return ""
    if "k" in text or "mil" in text:
        value *= 1000
    elif "m" in text or "mill" in text:
        value *= 1_000_000
    return str(int(value))

# ============================================================
# TWEET DATA EXTRACTION
# ============================================================

def extract_tweet_data(tweet_element, seed_tweet_id: str, nivel: int) -> Dict:
    """Return a base tweet record with default empty values."""
    return {
        "tweet_id": "",
        "seed_tweet_id": seed_tweet_id,
        "parent_tweet_id": "",
        "usuario_responde_a": "",
        "tipo_interaccion": "",
        "usuario_handle": "",
        "texto_tweet": "",
        "n_respuestas": "",
        "n_likes": "",
        "n_retuits": "",
        "fecha_publicacion": "",
        "enlace_tweet": "",
        "fecha_extraccion": datetime.now().isoformat(),
        "nivel": nivel,
        "tiene_imagen": 0,
        "tiene_video": 0,
    }


def extract_replying_to_user_hint(tweet_element) -> str:
    """Attempt to extract the target user of a reply from the DOM."""
    try:
        reply_links = tweet_element.find_elements(
            By.XPATH,
            ".//a[contains(@href,'https://x.com/') and not(contains(@href,'/status/')) and contains(., '@')]"
        )
        for link in reply_links:
            candidate_user = extract_user_from_profile_url(link.get_attribute("href") or "")
            text = (link.text or "").strip()
            if candidate_user and text.startswith("@"):
                return f"@{candidate_user}"
    except Exception:
        pass
    return ""


def completar_tweet_data(tweet_element, data: Dict) -> Dict:
    """Populate tweet record fields by reading the DOM element."""
    href = safe_get_attribute(tweet_element, "a[href*='/status/']", "href")
    if href:
        data["tweet_id"] = extract_status_id_from_url(href)
        data["enlace_tweet"] = href

    data["texto_tweet"] = safe_get_text(tweet_element, "[data-testid='tweetText']")
    data["fecha_publicacion"] = safe_get_attribute(tweet_element, "time", "datetime")

    try:
        links = tweet_element.find_elements(By.CSS_SELECTOR, "a[href]")
        for link in links:
            url = link.get_attribute("href") or ""
            if "/status/" not in url and url.startswith("https://x.com/"):
                user = url.rstrip("/").split("/")[-1]
                if user not in ["home", "explore", "i"]:
                    data["usuario_handle"] = f"@{user}"
                    break
    except Exception:
        pass

    reply_target_hint = ""
    try:
        reply_target_hint = extract_replying_to_user_hint(tweet_element)
        profile_links = tweet_element.find_elements(
            By.XPATH,
            ".//a[contains(@href,'https://x.com/') and not(contains(@href,'/status/'))]"
        )
        own_user = data["usuario_handle"].replace("@", "").lower().strip()
        for link in profile_links:
            url = link.get_attribute("href") or ""
            candidate_user = extract_user_from_profile_url(url)
            if candidate_user and candidate_user.lower() != own_user:
                if not reply_target_hint:
                    reply_target_hint = f"@{candidate_user}"
                break
    except Exception:
        pass

    try:
        buttons = tweet_element.find_elements(By.CSS_SELECTOR, "[role='button']")
        for btn in buttons:
            label_raw = btn.get_attribute("aria-label") or ""
            label = label_raw.lower()
            num = parse_count_from_label(label_raw)
            if not num:
                continue
            if "reply" in label or "respuesta" in label:
                data["n_respuestas"] = num
            elif "like" in label or "me gusta" in label:
                data["n_likes"] = num
            elif any(k in label for k in ["retweet", "retuite", "repost", "repostea"]):
                data["n_retuits"] = num
    except Exception:
        pass

    data["n_respuestas"] = data["n_respuestas"] if data["n_respuestas"] else "0"
    data["n_likes"] = data["n_likes"] if data["n_likes"] else "0"
    data["n_retuits"] = data["n_retuits"] if data["n_retuits"] else "0"

    data["parent_tweet_id"] = ""
    data["usuario_responde_a"] = reply_target_hint

    try:
        if data["tweet_id"] and data["tweet_id"] != data["seed_tweet_id"]:
            status_links = tweet_element.find_elements(By.XPATH, ".//a[contains(@href,'/status/')]")
            candidate_parents = []
            for link in status_links:
                url = link.get_attribute("href") or ""
                parent_user, status_id = extract_status_info_from_url(url)
                if status_id:
                    candidate_parents.append((status_id, parent_user))

            normalized_hint = data["usuario_responde_a"].replace("@", "").lower().strip()
            filtered = [
                (cid, cuser) for cid, cuser in candidate_parents
                if cid != data["tweet_id"] and cuser and cuser.lower().strip() == normalized_hint
            ]

            if filtered:
                candidate_id, candidate_user = filtered[0]
                data["parent_tweet_id"] = candidate_id
                data["usuario_responde_a"] = f"@{candidate_user}"
            else:
                for candidate_id, candidate_user in candidate_parents:
                    if candidate_id != data["tweet_id"]:
                        data["parent_tweet_id"] = candidate_id
                        if candidate_user:
                            data["usuario_responde_a"] = f"@{candidate_user}"
                        break
    except Exception:
        pass

    if data["tweet_id"] == data["seed_tweet_id"]:
        data["parent_tweet_id"] = ""
        data["usuario_responde_a"] = ""

    if (
        data["tweet_id"]
        and data["parent_tweet_id"]
        and data["tweet_id"] == data["parent_tweet_id"]
        and data["tweet_id"] != data["seed_tweet_id"]
    ):
        data["parent_tweet_id"] = ""
        data["usuario_responde_a"] = ""

    data["tipo_interaccion"] = "seed" if data["tweet_id"] == data["seed_tweet_id"] else "respuesta"

    return data

# ============================================================
# MEDIA EXTRACTION
# ============================================================

def extract_media(tweet_element, tweet_id: str) -> List[Dict]:
    """
    Detect images and videos attached to a tweet element.
    Note: file download is not performed — only presence is flagged.
    Emoji extraction is not supported in v1.0.
    """
    records = []
    idx = 1
    fecha = datetime.now().isoformat()

    try:
        images = tweet_element.find_elements(By.CSS_SELECTOR, "img[src*='pbs.twimg.com/media']")
        for img in images:
            src = img.get_attribute("src")
            if src:
                records.append({
                    "media_id": f"{tweet_id}_img_{idx}",
                    "tweet_id": tweet_id,
                    "tipo_media": "image",
                    "media_url": src,
                    "media_index": idx,
                    "fecha_extraccion": fecha
                })
                idx += 1
    except Exception:
        pass

    try:
        videos = tweet_element.find_elements(By.CSS_SELECTOR, "video")
        for vid in videos:
            src = vid.get_attribute("src")
            poster = vid.get_attribute("poster")
            media_url = src if src else poster
            if media_url:
                records.append({
                    "media_id": f"{tweet_id}_vid_{idx}",
                    "tweet_id": tweet_id,
                    "tipo_media": "video",
                    "media_url": media_url,
                    "media_index": idx,
                    "fecha_extraccion": fecha
                })
                idx += 1
    except Exception:
        pass

    return records

# ============================================================
# VISIBLE TWEET CAPTURE
# ============================================================

def extraer_visible(driver, seed_tweet_id: str, nivel: int = 0):
    """Capture all tweet elements currently visible in the browser."""
    tweet_elements = driver.find_elements(
        By.CSS_SELECTOR, "[data-testid='tweet'], article[role='article']"
    )
    print(f"    [*] Found {len(tweet_elements)} tweet elements on screen")

    tweets = []
    media = []

    for el in tweet_elements:
        try:
            base = extract_tweet_data(el, seed_tweet_id, nivel)
            tweet = completar_tweet_data(el, base)
            tweets.append(tweet)
            if tweet["tweet_id"]:
                media_items = extract_media(el, tweet["tweet_id"])
                media.extend(media_items)
        except Exception:
            continue

    print(f"    ✓ Extracted {len(tweets)} tweets")
    return pd.DataFrame(tweets), pd.DataFrame(media)

# ============================================================
# DERIVED VARIABLES
# ============================================================

def add_derived_media_variables(tweets_df: pd.DataFrame, media_df: pd.DataFrame):
    """Add binary media presence columns (tiene_imagen, tiene_video)."""
    tweets_df["tiene_imagen"] = 0
    tweets_df["tiene_video"] = 0

    if media_df.empty:
        return tweets_df

    summary = (
        media_df
        .groupby(["tweet_id", "tipo_media"])
        .size()
        .unstack(fill_value=0)
        .reset_index()
    )

    tweets_df = tweets_df.merge(summary, on="tweet_id", how="left")
    tweets_df["tiene_imagen"] = (tweets_df.get("image", 0) > 0).astype(int)
    tweets_df["tiene_video"] = (tweets_df.get("video", 0) > 0).astype(int)
    tweets_df = tweets_df.drop(columns=[c for c in ["image", "video"] if c in tweets_df.columns])

    return tweets_df

# ============================================================
# HIERARCHICAL LEVEL ASSIGNMENT
# ============================================================

def calculate_levels(tweets_df: pd.DataFrame, seed_tweet_id: str) -> pd.DataFrame:
    """
    Assign hierarchical level to each tweet based on parent_tweet_id.
    Level 0 = seed tweet; level n+1 = reply to a tweet at level n.
    Iterates until no new assignments can be made.
    """
    if tweets_df.empty:
        return tweets_df

    tweets_df['tweet_id'] = tweets_df['tweet_id'].fillna("").astype(str).str.strip()
    tweets_df['parent_tweet_id'] = tweets_df['parent_tweet_id'].fillna("").astype(str).str.strip()

    auto_parent_mask = (
        (tweets_df['tweet_id'] == tweets_df['parent_tweet_id'])
        & (tweets_df['tweet_id'] != seed_tweet_id)
    )
    tweets_df.loc[auto_parent_mask, 'parent_tweet_id'] = ""

    levels: Dict[str, int] = {seed_tweet_id: 0}

    changed = True
    while changed:
        changed = False
        for _, row in tweets_df.iterrows():
            tid = row['tweet_id']
            pid = row['parent_tweet_id']
            if not tid or tid in levels:
                continue
            if pid and pid in levels:
                levels[tid] = levels[pid] + 1
                changed = True

    tweets_df['nivel'] = tweets_df['tweet_id'].map(levels).astype('Int64')
    return tweets_df

# ============================================================
# PARENT INFERENCE
# ============================================================

def assign_reply_user_from_parent_map(tweets_df: pd.DataFrame, seed_tweet_id: str) -> pd.DataFrame:
    """
    Populate usuario_responde_a using parent_tweet_id → usuario_handle lookup.
    Falls back to DOM-extracted value when parent is not in the dataset.
    """
    if tweets_df.empty:
        return tweets_df

    if 'usuario_responde_a' not in tweets_df.columns:
        tweets_df['usuario_responde_a'] = ""

    tweets_df['tweet_id'] = tweets_df['tweet_id'].fillna("").astype(str).str.strip()
    tweets_df['parent_tweet_id'] = tweets_df['parent_tweet_id'].fillna("").astype(str).str.strip()
    tweets_df['usuario_handle'] = tweets_df['usuario_handle'].fillna("").astype(str).str.strip()

    parent_lookup = (
        tweets_df[['tweet_id', 'usuario_handle']]
        .drop_duplicates(subset=['tweet_id'])
        .rename(columns={
            'tweet_id': 'lookup_parent_tweet_id',
            'usuario_handle': 'lookup_parent_usuario_handle'
        })
    )

    tweets_df = tweets_df.merge(
        parent_lookup,
        left_on='parent_tweet_id',
        right_on='lookup_parent_tweet_id',
        how='left'
    )

    mapped_parent_user = tweets_df['lookup_parent_usuario_handle'].fillna("").astype(str).str.strip()
    existing_reply_user = tweets_df['usuario_responde_a'].fillna("").astype(str).str.strip()
    tweets_df['usuario_responde_a'] = mapped_parent_user.where(mapped_parent_user != "", existing_reply_user)

    no_parent_mask = (tweets_df['parent_tweet_id'] == "") | (tweets_df['tweet_id'] == seed_tweet_id)
    tweets_df.loc[no_parent_mask, 'usuario_responde_a'] = ""

    tweets_df = tweets_df.drop(columns=[
        c for c in ['lookup_parent_tweet_id', 'lookup_parent_usuario_handle']
        if c in tweets_df.columns
    ])

    return tweets_df


def infer_missing_parent_tweet_ids(tweets_df: pd.DataFrame, seed_tweet_id: str) -> pd.DataFrame:
    """
    Infer parent_tweet_id for replies where DOM extraction failed.

    Strategy:
    1. Match by usuario_responde_a → usuario_handle of candidate parent tweets.
    2. Among matches, prefer the temporally closest predecessor.
    3. If no temporal data, fall back to row order.
    4. Final fallback: assign the immediately preceding tweet in capture order.
    """
    if tweets_df.empty:
        return tweets_df

    tweets_df['tweet_id'] = tweets_df['tweet_id'].fillna("").astype(str).str.strip()
    tweets_df['parent_tweet_id'] = tweets_df['parent_tweet_id'].fillna("").astype(str).str.strip()
    tweets_df['usuario_handle'] = tweets_df['usuario_handle'].fillna("").astype(str).str.strip()
    tweets_df['usuario_responde_a'] = tweets_df['usuario_responde_a'].fillna("").astype(str).str.strip()

    if 'fecha_publicacion' in tweets_df.columns:
        tweets_df['_fecha_pub_dt'] = pd.to_datetime(tweets_df['fecha_publicacion'], errors='coerce', utc=True)
    else:
        tweets_df['_fecha_pub_dt'] = pd.NaT

    tweets_df = tweets_df.reset_index(drop=True)
    tweets_df['_row_order'] = tweets_df.index

    for idx, row in tweets_df.iterrows():
        tid = row['tweet_id']
        pid = row['parent_tweet_id']
        target_user = row['usuario_responde_a']

        if not tid or tid == seed_tweet_id or pid or not target_user:
            continue

        candidates = tweets_df[
            (tweets_df['usuario_handle'] == target_user)
            & (tweets_df['tweet_id'] != tid)
            & (tweets_df['tweet_id'] != "")
        ].copy()

        if candidates.empty:
            continue

        child_dt = row['_fecha_pub_dt']
        if pd.notna(child_dt):
            candidates_time = candidates[
                candidates['_fecha_pub_dt'].notna()
                & (candidates['_fecha_pub_dt'] <= child_dt)
            ]
            if not candidates_time.empty:
                parent_row = candidates_time.sort_values('_fecha_pub_dt', ascending=False).iloc[0]
                tweets_df.at[idx, 'parent_tweet_id'] = parent_row['tweet_id']
                continue

        candidates_order = candidates[candidates['_row_order'] < row['_row_order']]
        if not candidates_order.empty:
            parent_row = candidates_order.sort_values('_row_order', ascending=False).iloc[0]
            tweets_df.at[idx, 'parent_tweet_id'] = parent_row['tweet_id']
            continue

        previous_rows = tweets_df[
            (tweets_df['_row_order'] < row['_row_order'])
            & (tweets_df['tweet_id'] != "")
            & (tweets_df['tweet_id'] != tid)
        ]
        if not previous_rows.empty:
            parent_row = previous_rows.sort_values('_row_order', ascending=False).iloc[0]
            tweets_df.at[idx, 'parent_tweet_id'] = parent_row['tweet_id']

    tweets_df = tweets_df.drop(columns=[
        c for c in ['_fecha_pub_dt', '_row_order'] if c in tweets_df.columns
    ])
    return tweets_df

# ============================================================
# CSV OUTPUT
# ============================================================

def save_csv(df: pd.DataFrame, filename: str):
    """Save DataFrame to CSV with UTF-8 BOM encoding."""
    if df.empty:
        print("⚠ No data to save:", filename)
        return
    df.to_csv(filename, index=False, encoding="utf-8-sig")
    print("Saved:", filename)

# ============================================================
# MAIN
# ============================================================

def main():
    print("=" * 80)
    print("SEMI-MANUAL HIERARCHICAL EXTRACTOR FOR X (TWITTER) REPLY THREADS")
    print("v1.0 — David Gómez Cabrera (2026)")
    print("=" * 80)
    print()

    csv_name = input("Output CSV filename (without extension)\n→ ").strip()
    if not csv_name:
        csv_name = OUTPUT_CSV_DEFAULT.replace(".csv", "")
        print(f"Using default name: {csv_name}\n")
    else:
        csv_name = csv_name.replace(".csv", "")

    tweets_file = f"{csv_name}.csv"
    print(f"✓ Output will be saved to: {tweets_file}\n")

    seed_id = input("Enter the ID of the SEED tweet\n→ ").strip()
    if not seed_id:
        print("✗ Invalid ID")
        return

    print("\n" + "=" * 80)
    print("LAUNCHING BROWSER")
    print("=" * 80)

    driver = init_driver()
    time.sleep(1)

    print("\n✓ Browser launched. Log in to X if required.")
    input("Press ENTER to continue...")

    print("\n" + "=" * 80)
    print("NAVIGATING TO SEED TWEET")
    print("=" * 80)

    url_principal = f"https://x.com/i/status/{seed_id}"
    print(f"\nOpening: {url_principal}")
    driver.get(url_principal)

    try:
        WebDriverWait(driver, 10).until(
            EC.presence_of_element_located(
                (By.CSS_SELECTOR, "[data-testid='tweet'], article[role='article']")
            )
        )
    except Exception as e:
        print(f"✗ Error waiting for tweets: {e}")
        driver.quit()
        return

    print("✓ Page loaded\n")

    accumulated_tweets = []
    accumulated_media = []
    capture_count = 0
    context_seed_stack = [seed_id]
    known_tweet_users = {}

    while True:
        current_depth = len(context_seed_stack) - 1
        current_parent_seed_id = context_seed_stack[-1]

        print("    " + "-" * 76)
        if current_depth == 0:
            prompt = (
                f"    [Level {current_depth}] Active seed: {current_parent_seed_id}\n"
                "    Commands: ENTER (capture) / end / d (go deeper)\n"
                "    → "
            )
        else:
            prompt = (
                f"    [Level {current_depth}] Active seed: {current_parent_seed_id}\n"
                "    Commands: ENTER (capture) / b (go back) / d (go deeper)\n"
                "    → "
            )

        try:
            user_input = input(prompt).strip().lower()
        except KeyboardInterrupt:
            print("\n    ✗ Ctrl+C detected. Use 'end' to exit and save progress.")
            continue

        if current_depth == 0 and user_input == "end":
            print("    ✓ Ending capture...")
            break

        if user_input in ["deep", "d"]:
            try:
                next_seed_id = input(
                    f"    Enter the ID of the tweet to capture replies for (level {current_depth + 1})\n"
                    "    → "
                ).strip()
            except KeyboardInterrupt:
                print("\n    ✗ Ctrl+C detected. Operation cancelled.")
                continue
            if not next_seed_id:
                print("    ✗ Invalid ID. Level unchanged.")
                continue
            context_seed_stack.append(next_seed_id)
            print(f"    ✓ Going deeper to level {len(context_seed_stack) - 1} with seed {next_seed_id}")
            continue

        if user_input in ["b", "back"]:
            if current_depth == 0:
                print("    ✗ Already at root level. Use ENTER, d or end.")
                continue
            context_seed_stack.pop()
            print(f"    ✓ Back to level {current_depth - 1} (active seed: {context_seed_stack[-1]})")
            continue

        if user_input == "":
            capture_count += 1
            print(f"\n    [Capture #{capture_count}] Capturing visible tweets at level {current_depth}...")

            df_tweets, df_media = extraer_visible(driver, seed_id, nivel=current_depth)

            if not df_tweets.empty:
                parent_user = known_tweet_users.get(current_parent_seed_id, "")
                if not parent_user:
                    same_seed_rows = df_tweets[
                        (df_tweets['tweet_id'] == current_parent_seed_id)
                        & (df_tweets['usuario_handle'].fillna("") != "")
                    ]
                    if not same_seed_rows.empty:
                        parent_user = str(same_seed_rows.iloc[0]['usuario_handle']).strip()
                        if parent_user:
                            known_tweet_users[current_parent_seed_id] = parent_user

                non_seed_mask = df_tweets['tweet_id'] != current_parent_seed_id
                df_tweets.loc[non_seed_mask, 'parent_tweet_id'] = current_parent_seed_id
                if parent_user:
                    df_tweets.loc[non_seed_mask, 'usuario_responde_a'] = parent_user

                global_seed_mask = df_tweets['tweet_id'] == seed_id
                df_tweets.loc[global_seed_mask, 'tipo_interaccion'] = 'seed'
                df_tweets.loc[~global_seed_mask, 'tipo_interaccion'] = 'respuesta'

                antes = len(df_tweets)
                df_tweets = df_tweets.drop_duplicates(subset=["tweet_id"], keep="first")
                duplicados = antes - len(df_tweets)

                for _, row in df_tweets.iterrows():
                    tid = str(row.get('tweet_id', '')).strip()
                    user_handle = str(row.get('usuario_handle', '')).strip()
                    if tid and user_handle:
                        known_tweet_users[tid] = user_handle

                accumulated_tweets.extend(df_tweets.to_dict('records'))

                total_antes = len(accumulated_tweets)
                unique_ids = {}
                for record in accumulated_tweets:
                    tweet_id = record.get('tweet_id', '')
                    if tweet_id and tweet_id not in unique_ids:
                        unique_ids[tweet_id] = record
                accumulated_tweets = list(unique_ids.values())
                eliminados_acumulado = total_antes - len(accumulated_tweets)

                print(f"    ✓ Unique tweets in this capture: {len(df_tweets)}")
                if duplicados > 0:
                    print(f"    [Dedup] Removed {duplicados} duplicates in this capture")
                if eliminados_acumulado > 0:
                    print(f"    [Dedup] Removed {eliminados_acumulado} duplicates from accumulator")
                print(f"    ✓ Total accumulated: {len(accumulated_tweets)} unique tweets")

                if not df_media.empty:
                    accumulated_media.extend(df_media.to_dict('records'))
            else:
                print("    ⚠ No tweets found in this capture")
            print()
            continue

        if current_depth == 0:
            print("    ✗ Unrecognised command. Use ENTER / end / d")
        else:
            print("    ✗ Unrecognised command. Use ENTER / b / d")
        continue

    driver.quit()

    print("\n" + "=" * 80)
    print("FINALISING EXTRACTION")
    print("=" * 80 + "\n")

    tweets_df = pd.DataFrame(accumulated_tweets) if accumulated_tweets else pd.DataFrame()
    media_df = pd.DataFrame(accumulated_media) if accumulated_media else pd.DataFrame()

    if not tweets_df.empty:
        tweets_df['tweet_id'] = tweets_df['tweet_id'].fillna("").astype(str).str.strip()
        tweets_df = tweets_df[tweets_df['tweet_id'] != ""]
        tweets_df = tweets_df.drop_duplicates(subset=['tweet_id'], keep='first').copy()

        tweets_df = infer_missing_parent_tweet_ids(tweets_df, seed_id)
        tweets_df = assign_reply_user_from_parent_map(tweets_df, seed_id)
        tweets_df = calculate_levels(tweets_df, seed_id)
        tweets_df = add_derived_media_variables(tweets_df, media_df)

        columns_to_drop = [
            'tweet_semilla_principal', 'respuesta_nivel_1', 'respuesta_nivel_2',
            'respuesta_nivel_3', 'num_media', 'num_imagenes', 'num_videos', 'media_items'
        ]
        tweets_df = tweets_df.drop(columns=[c for c in columns_to_drop if c in tweets_df.columns])

    save_csv(tweets_df, tweets_file)
    print("\n✓ Extraction complete")


# ============================================================
if __name__ == "__main__":
    main()
