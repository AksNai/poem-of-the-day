"""Fetch the Poetry Foundation 'Poem of the Day' and write poem.json.

Strategy
--------
1. Use Jina Reader (r.jina.ai) to get a Markdown render of the
   Poem-of-the-Day landing page.  Extract the first poem URL.
2. Fetch the raw HTML of the individual poem page via allorigins
   proxy and extract the poem from the embedded __NUXT_DATA__
   JSON.  This gives us the real formatting: <i>, <em>, <strong>,
   <div style="font-style:italic"> (dedications/epigraphs), and
   &nbsp; indentation.
3. Convert the HTML to Markdown (_italic_, **bold**, preserved
   whitespace).
4. Fall back to Jina Markdown parsing when NUXT extraction fails.
5. If all network sources fail, keep the existing poem.json untouched.

Every response is decoded as UTF-8 explicitly to avoid mojibake.
"""

import json
import re
from html import unescape
from html.parser import HTMLParser
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

# Boilerplate tokens that may appear BEFORE the poem body — used to skip
# navigation, headers, and sidebar items.
_PRE_SKIP_PATTERN = re.compile(
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

# Tokens that signal the END of the poem body.
# NOTE: month names are deliberately excluded — they can appear in poems
# (e.g. "April is the cruellest month" in The Waste Land).
_POST_STOP_PATTERN = re.compile(
    r"^("
    r"Poems & Poets|Topics & Themes|Features|Grants & Programs|About Us|"
    r"Poetry magazine|Subscribe|Related|More by|Advertise|"
    r"A note from the editor|Sign Up|"
    r"RECENT POEMS OF THE DAY|Poetry Foundation Homepage|"
    r"Skip to main content|Donate|"
    r"THIS POEM HAS A POEM GUIDE|View Poem Guide"
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


def fetch_html(url: str) -> str | None:
    """Fetch the raw HTML of *url* via CORS proxies.

    Tries multiple free proxies with retry.  Returns ``None`` on failure.
    """
    import time
    # Normalise to https
    norm = re.sub(r"^http://", "https://", url, flags=re.I)

    proxies = [
        f"https://api.allorigins.win/raw?url={quote(norm, safe='')}",
        f"https://api.codetabs.com/v1/proxy?quest={quote(norm, safe='')}",
    ]

    for proxy_url in proxies:
        for attempt in range(2):
            try:
                return _get_text(proxy_url)
            except Exception:
                if attempt == 0:
                    time.sleep(2)
        # Small pause between proxies
        time.sleep(1)

    print("  fetch_html: all proxies failed")
    return None


# ---------------------------------------------------------------------------
# HTML → Markdown converter  (for NUXT poem data)
# ---------------------------------------------------------------------------

class _PoemHTMLToMarkdown(HTMLParser):
    """Convert a fragment of poem HTML to Markdown-flavoured text.

    Handles:
      <i>, <em>                        → _italic_
      <b>, <strong>                    → **bold**
      <div style="font-style:italic"> → _italic block_
      <br>, <br/>                      → newline
      <p>…</p>                         → paragraph break
      &nbsp;                           → regular space
      <span style="display:none">      → stripped (PF annotations)
      <a href="…">text</a>            → text  (links stripped)
      <span class="annotation">text    → text  (keep visible)
    """

    def __init__(self):
        super().__init__()
        self.parts: list[str] = []
        self._italic = 0          # nesting depth
        self._bold = 0
        self._hidden = 0          # inside display:none spans
        self._tag_stack: list[tuple[str, dict]] = []

    # -- helpers ----------------------------------------------------------

    def _style(self, attrs: dict) -> str:
        return attrs.get("style", "")

    def _is_italic_style(self, style: str) -> bool:
        return "font-style:italic" in style or "font-style: italic" in style

    def _is_hidden_style(self, style: str) -> bool:
        return "display:none" in style or "display: none" in style

    # -- parser callbacks -------------------------------------------------

    def handle_starttag(self, tag: str, attrs: list):
        ad = dict(attrs)
        style = self._style(ad)

        # Hidden annotation text (Poetry Foundation uses this for glosses)
        if self._is_hidden_style(style):
            self._hidden += 1
            self._tag_stack.append((tag, {"hidden_open": True}))
            return

        self._tag_stack.append((tag, ad))
        if self._hidden:
            return

        if tag in ("i", "em"):
            self.parts.append("_")
            self._italic += 1
        elif tag == "div" and self._is_italic_style(style):
            self.parts.append("_")
            self._italic += 1
        elif tag in ("b", "strong"):
            self.parts.append("**")
            self._bold += 1
        elif tag == "br":
            self.parts.append("\n")

    def handle_endtag(self, tag: str):
        # Pop the matching entry off the stack
        popped = {}
        if self._tag_stack:
            ptag, pattrs = self._tag_stack.pop()
            popped = pattrs
            # Handle nesting: if we opened a hidden span, close it
            if popped.get("hidden_open"):
                self._hidden = max(0, self._hidden - 1)
                return

        if self._hidden:
            return

        if tag in ("i", "em"):
            if self._italic > 0:
                self.parts.append("_")
                self._italic -= 1
        elif tag == "div":
            if self._italic > 0 and self._is_italic_style(self._style(popped)):
                # Move trailing whitespace AFTER the closing marker
                # so _text\n\n_ becomes _text_\n\n
                trailing_ws = ""
                while self.parts and self.parts[-1].strip() == "":
                    trailing_ws = self.parts.pop() + trailing_ws
                self.parts.append("_")
                self._italic -= 1
                if trailing_ws:
                    self.parts.append(trailing_ws)
        elif tag in ("b", "strong"):
            if self._bold > 0:
                self.parts.append("**")
                self._bold -= 1
        elif tag == "p":
            self.parts.append("\n\n")

    def handle_data(self, data: str):
        if not self._hidden:
            # Strip literal \r\n from source HTML — line breaks are
            # handled by <br> tags; the \r\n after <br> in PF's HTML
            # is just source formatting, not meaningful whitespace.
            cleaned = data.replace('\r\n', '').replace('\r', '').replace('\n', '')
            if cleaned:
                self.parts.append(cleaned)

    def handle_entityref(self, name: str):
        if not self._hidden:
            if name == "nbsp":
                self.parts.append(" ")
            elif name in ("mdash", "#8212"):
                self.parts.append("—")
            elif name in ("ndash", "#8211"):
                self.parts.append("–")
            elif name in ("ldquo", "rdquo", "lsquo", "rsquo"):
                mapping = {"ldquo": "\u201c", "rdquo": "\u201d",
                           "lsquo": "\u2018", "rsquo": "\u2019"}
                self.parts.append(mapping.get(name, "'"))
            else:
                self.parts.append(unescape(f"&{name};"))

    def handle_charref(self, name: str):
        if not self._hidden:
            try:
                if name.startswith("x"):
                    self.parts.append(chr(int(name[1:], 16)))
                else:
                    self.parts.append(chr(int(name)))
            except (ValueError, OverflowError):
                self.parts.append(f"&#{name};")

    def get_markdown(self) -> str:
        return "".join(self.parts)


def html_to_markdown(html_fragment: str) -> str:
    """Convert a poem HTML fragment to Markdown with formatting."""
    parser = _PoemHTMLToMarkdown()
    parser.feed(html_fragment)
    text = parser.get_markdown()

    # Normalise whitespace: collapse runs of 3+ newlines → 2
    text = re.sub(r"\n{3,}", "\n\n", text)

    # Trim trailing whitespace on each line (PF sometimes has trailing &nbsp;)
    text = "\n".join(ln.rstrip() for ln in text.splitlines())

    return text.strip()


# ---------------------------------------------------------------------------
# NUXT data extraction
# ---------------------------------------------------------------------------

def extract_poem_from_nuxt(page_html: str) -> str | None:
    """Extract the poem body as Markdown from __NUXT_DATA__ in *page_html*.

    Returns the poem body string (with Markdown formatting) or None.
    """
    m = re.search(
        r'<script[^>]*id="__NUXT_DATA__"[^>]*>(.*?)</script>',
        page_html,
        re.S,
    )
    if not m:
        return None

    try:
        data = json.loads(m.group(1))
    except (json.JSONDecodeError, ValueError):
        return None

    # 1. Find the poem body <p> element.
    #    Poems have a HIGH ratio of <br> tags to text length (short lines)
    #    and typically no visible <a> links.  Prose passages (bios, essays)
    #    have low br-ratio and contain hyperlinks.
    #
    #    Exception: some poems (e.g. The Waste Land) have <a> links inside
    #    hidden annotation <span style="display:none"> — we don't count those.
    best_html = ""
    best_score = -1.0

    for item in data:
        if not isinstance(item, str):
            continue
        if not item.lstrip().startswith("<p") or item.count("<br") < 3:
            continue

        text = re.sub(r"<[^>]+>", "", item)
        text = re.sub(r"&\w+;", " ", text)
        text_len = len(text.strip())
        if text_len < 50:
            continue

        br_count = item.count("<br")
        br_ratio = br_count / max(1, text_len)

        # Check for visible links (links NOT inside display:none spans).
        # PF annotation spans look like:
        #   <span style="display:none;">...<a href="...">...</a>...</span>
        # Strip those hidden sections first, then check for remaining <a>.
        visible = re.sub(
            r'<span[^>]*display:\s*none[^>]*>.*?</span>',
            "", item, flags=re.S | re.I,
        )
        has_visible_links = "<a " in visible

        # Poems: high br_ratio (≥ 0.005), no visible links
        # Prose: low br_ratio, has visible links
        if has_visible_links and br_ratio < 0.01:
            continue                    # Definitely prose
        if br_ratio < 0.003:
            continue                    # Too few line breaks for a poem

        # Among remaining candidates, prefer the longest one
        # (short ones might be excerpts).  Bonus for high br_ratio.
        score = text_len * (1 + br_ratio * 100)
        if score > best_score:
            best_score = score
            best_html = item

    if not best_html:
        return None

    # 2. Find epigraph / dedication: <div style="font-style:italic">
    #    These are short italic blocks (dedications like "(for Harlem Magic)")
    epigraph = ""
    for item in data:
        if not isinstance(item, str):
            continue
        if re.match(
            r'<div\s[^>]*font-style:\s*italic[^>]*>',
            item, re.I,
        ):
            text = html_to_markdown(item)
            # Dedications/epigraphs are short; skip long prose passages
            if text and len(text) < 300:
                # The html_to_markdown already wraps it in _..._
                epigraph = text

    # 3. Convert poem body HTML → Markdown
    body = html_to_markdown(best_html)
    if not body:
        return None

    # 4. Return body and epigraph separately
    result = {"body": body}
    if epigraph:
        # Check the epigraph text isn't already embedded in the body
        plain_epi = epigraph.replace("_", "").replace("*", "").strip()
        if plain_epi not in body.replace("_", "").replace("*", ""):
            # Strip the outer italic markers — the epigraph field is
            # semantically "this is an epigraph"; rendering decides style.
            epi_clean = epigraph.strip()
            if epi_clean.startswith("_") and epi_clean.endswith("_"):
                epi_clean = epi_clean[1:-1].strip()
            result["epigraph"] = epi_clean

    return result


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
            if _PRE_SKIP_PATTERN.match(stripped):
                continue
            started = True

        # Stop at navigation / footer boilerplate (no month names here!)
        if started and _POST_STOP_PATTERN.match(stripped):
            break
        # Stop at Markdown headings (####, ###, etc.) — navigational
        if started and re.match(r"^#{2,}\s", stripped):
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

    # 3. Fetch the poem page via Jina (for title/author, and fallback body)
    poem_md = fetch_markdown(poem_url)
    jina_data = parse_poem_markdown(poem_md)

    # 4. Try NUXT HTML extraction for rich formatting of the body
    data = None
    page_html = fetch_html(poem_url)
    if page_html:
        nuxt_result = extract_poem_from_nuxt(page_html)
        if nuxt_result:
            nuxt_body = nuxt_result["body"]
            data = {
                "title": jina_data["title"],
                "author": jina_data["author"],
                "poem": nuxt_body,
            }
            if nuxt_result.get("epigraph"):
                data["epigraph"] = nuxt_result["epigraph"]
            if is_valid(data):
                print("  (used NUXT HTML for rich formatting)")
            else:
                data = None

    # 5. Fall back to Jina-only parsing
    if data is None or not is_valid(data):
        data = jina_data
        print("  (used Jina Markdown)")

    if not is_valid(data):
        # Last resort: try parsing the landing page markdown itself
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

    # 6. Write output
    OUT_FILE.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {data['title']!r} by {data['author']!r} ({len(data['poem'])} chars)")


if __name__ == "__main__":
    main()
