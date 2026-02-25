"""Fetch the Poetry Foundation 'Poem of the Day' and write poem.json.

Strategy
--------
1. Use Jina Reader (r.jina.ai) to get a Markdown render of the
   Poem-of-the-Day landing page.  Extract the first poem URL.
2. Fetch the individual poem page (again via Jina) and parse title,
   author, and full poem text from the Markdown.
3. Fall back to the allorigins CORS proxy when Jina is unavailable.
4. If all network sources fail, keep the existing poem.json untouched.

Every response is decoded as UTF-8 explicitly to avoid mojibake.
"""

import json
import re
from pathlib import Path
from urllib.parse import quote

import requests

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

POD_URL = "https://www.poetryfoundation.org/poems/poem-of-the-day"
OUT_FILE = Path(__file__).resolve().parents[1] / "poem.json"

_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,*/*",
}

_TIMEOUT = 30  # seconds

# Sections we never want leaking into the poem body
_STOP_PATTERN = re.compile(
    r"^("
    r"Poems & Poets|Topics & Themes|Features|Grants & Programs|About Us|"
    r"Poetry magazine|Subscribe|Related|More by|Advertise|Copyright|"
    r"Source[:.]|Share|A note from the editor|Sign Up|"
    r"RECENT POEMS OF THE DAY|Poetry Foundation Homepage|"
    r"Skip to main content|Read More|Donate|Listen|"
    r"January|February|March|April|May|June|July|August|"
    r"September|October|November|December"
    r")\b",
    re.I,
)

_BOILERPLATE_EXACT = {
    "Share",
    "Play Audio",
    "Donate",
    "Listen",
    "Read More",
    "Read more",
}


# ---------------------------------------------------------------------------
# Network helpers — always decode as UTF-8
# ---------------------------------------------------------------------------

def _jina_url(url: str) -> str:
    """Build a Jina Reader URL for *url*."""
    bare = re.sub(r"^https?://", "", url.strip(), flags=re.I)
    return f"https://r.jina.ai/http://{bare}"


def _allorigins_url(url: str) -> str:
    return f"https://api.allorigins.win/raw?url={quote(url, safe='')}"


def _get_text(url: str) -> str:
    """GET *url* and return text, always decoded as UTF-8."""
    r = requests.get(url, timeout=_TIMEOUT, headers=_HEADERS)
    r.raise_for_status()
    # Always use raw bytes → UTF-8 to avoid requests guessing wrong
    return r.content.decode("utf-8", errors="replace")


def fetch_markdown(url: str) -> str:
    """Return Markdown (via Jina) or raw HTML as a last resort."""
    errors: list[str] = []
    for source_fn in (_jina_url, _allorigins_url):
        try:
            return _get_text(source_fn(url))
        except Exception as exc:
            errors.append(f"{source_fn.__name__}: {exc}")
    raise RuntimeError(
        f"All sources failed for {url}:\n" + "\n".join(errors)
    )


# ---------------------------------------------------------------------------
# URL extraction
# ---------------------------------------------------------------------------

_POEM_URL_RE = re.compile(
    r"https?://(?:www\.)?poetryfoundation\.org/"
    r"(?:poems|poetrymagazine/poems)/\d+[^\s)\]\"']*",
    re.I,
)


def _is_individual_poem(url: str) -> bool:
    return bool(_POEM_URL_RE.match(url)) and "poem-of-the-day" not in url.lower()


def _clean_url(url: str) -> str:
    return re.sub(r"[\s\"'`.,;:!?\])}>]+$", "", url.strip())


def extract_poem_url(markdown: str) -> str | None:
    """Find the first individual poem URL in *markdown*."""
    # Prefer an explicit [Read More](…) link
    for m in re.finditer(r"\[([^\]]*)\]\((https?://[^)]+)\)", markdown):
        link = _clean_url(m.group(2))
        if _is_individual_poem(link):
            return link

    # Fall back to any bare poem URL
    for m in _POEM_URL_RE.finditer(markdown):
        link = _clean_url(m.group(0))
        if _is_individual_poem(link):
            return link

    return None


# ---------------------------------------------------------------------------
# Markdown → poem parsing
# ---------------------------------------------------------------------------

def _strip_md_links(text: str) -> str:
    return re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)


def parse_poem_markdown(text: str) -> dict:
    """Parse Jina-style Markdown into {title, author, poem}."""

    # ── Extract Jina metadata header ──────────────────────
    jina_title = ""
    md_body = text
    if "Markdown Content:" in text:
        header, md_body = text.split("Markdown Content:", 1)
        m = re.search(r"^Title:\s*(.+)", header, re.M)
        if m:
            jina_title = m.group(1).strip()

    lines = [_strip_md_links(ln.rstrip()) for ln in md_body.splitlines()]

    # ── Title — use the LAST setext heading (=== underlined) ──
    # The first one is the page title with "| The Poetry Foundation",
    # the last one before "By" is the real poem title.
    title = ""
    title_end_idx = 0
    for i in range(len(lines) - 1):
        if lines[i].strip() and set(lines[i + 1].strip()) == {"="}:
            title = lines[i].strip()
            title_end_idx = i + 2

    # Strip site suffix ("… | The Poetry Foundation")
    if " | " in title:
        title = title.split(" | ", 1)[0].strip()

    # Prefer Jina metadata title (always clean)
    if jina_title:
        title = jina_title

    # ── Author — search from the last heading onward ──────
    author = ""
    author_end_idx = title_end_idx
    for i in range(title_end_idx, len(lines)):
        stripped = lines[i].strip()
        if stripped.lower().startswith("by "):
            author = stripped[3:].strip()
            author_end_idx = i + 1
            break
        if stripped.lower() == "by":
            for j in range(i + 1, len(lines)):
                if lines[j].strip():
                    author = lines[j].strip()
                    author_end_idx = j + 1
                    break
            break
        # Don't search forever — stop if we hit something that
        # looks like poem content (multiple non-short lines in a row)
        if i > title_end_idx + 30:
            break

    # Clean trailing junk from author ("Listen to…", dates, etc.)
    author = re.sub(r"\s*Listen.*$", "", author, flags=re.I).strip()
    author = re.sub(r"\s*\d{4}\s*[-–—].*$", "", author).strip()

    # ── Poem body ──────────────────────────────────────────
    body_lines: list[str] = []
    started = False
    for ln in lines[author_end_idx:]:
        stripped = ln.strip()

        # Skip blanks and boilerplate before the poem starts
        if not started:
            if not stripped or stripped in _BOILERPLATE_EXACT:
                continue
            if stripped.startswith("[]("):           # empty MD images
                continue
            if _STOP_PATTERN.match(stripped):
                continue
            started = True

        # Stop at navigation / footer boilerplate
        if started and _STOP_PATTERN.match(stripped):
            break
        # Stop at horizontal rules (---) which Jina uses as section breaks
        if started and re.match(r"^[-_*]{3,}\s*$", stripped):
            break
        # Stop at copyright / source lines
        if started and re.match(r"^(Copyright|Source[:\s])", stripped, re.I):
            break

        body_lines.append(ln)

    # Trim leading/trailing blank lines
    while body_lines and not body_lines[0].strip():
        body_lines.pop(0)
    while body_lines and not body_lines[-1].strip():
        body_lines.pop()

    poem = "\n".join(body_lines)

    return {"title": title, "author": author, "poem": poem}


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

_BLOCKED_TOKENS = (
    "window.__nuxt__",
    "primarynavigation_node",
    "cachetags",
    "<script",
    "poetry foundation homepage",
    "sign up to receive the poem of the day",
    "poetrymagazine archive",
    "advertise withpoetry",
)


def is_valid(data: dict) -> bool:
    poem = (data.get("poem") or "").strip()
    if not poem:
        return False
    if len(poem) > 20_000 or poem.count("\n") > 1200:
        return False
    low = poem.lower()
    return not any(tok in low for tok in _BLOCKED_TOKENS)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    # 1. Get the Poem-of-the-Day landing page via Jina
    pod_md = fetch_markdown(POD_URL)

    # 2. Extract the individual poem URL
    poem_url = extract_poem_url(pod_md)
    if not poem_url:
        raise RuntimeError("Could not find an individual poem URL on the landing page.")

    print(f"Poem URL: {poem_url}")

    # 3. Fetch & parse the poem page
    poem_md = fetch_markdown(poem_url)
    data = parse_poem_markdown(poem_md)

    if not is_valid(data):
        # Last resort: try parsing the landing page markdown itself
        # (sometimes Jina inlines the full poem there)
        data = parse_poem_markdown(pod_md)

    if not is_valid(data):
        # Don't overwrite a good poem.json with garbage
        if OUT_FILE.exists():
            try:
                existing = json.loads(OUT_FILE.read_text(encoding="utf-8"))
                if existing.get("poem"):
                    print("WARNING: extraction failed; keeping existing poem.json")
                    return
            except (json.JSONDecodeError, OSError):
                pass
        raise RuntimeError("Could not extract poem text; poem.json was not updated.")

    # 4. Write output
    OUT_FILE.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {data['title']!r} by {data['author']!r} ({len(data['poem'])} chars)")


if __name__ == "__main__":
    main()
