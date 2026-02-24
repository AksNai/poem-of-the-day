import json
import re
from pathlib import Path
from urllib.parse import quote

import requests
from bs4 import BeautifulSoup

POD_URL = "https://www.poetryfoundation.org/poems/poem-of-the-day"
BASE_URL = "https://www.poetryfoundation.org"
OUT_FILE = Path(__file__).resolve().parents[1] / "poem.json"


def build_jina_reader_url(url: str) -> str:
    # r.jina.ai expects the target without its leading scheme.
    target = re.sub(r"^https?://", "", url.strip(), flags=re.I)
    return f"https://r.jina.ai/http://{target}"


def clean_text(text: str) -> str:
    return (
        text.replace("\u00a0", " ")
        .replace("\r\n", "\n")
        .replace("\r", "\n")
        .strip("\n")
    )


def fetch_html(url: str) -> str:
    sources = [
        (url, True),
        (f"https://api.allorigins.win/raw?url={quote(url, safe='')}", False),
    ]

    for source, use_headers in sources:
        try:
            response = requests.get(
                source,
                timeout=25,
                headers={"User-Agent": "Mozilla/5.0"} if use_headers else None,
            )
            if response.status_code >= 400:
                continue
            if response.text and "<html" in response.text.lower():
                return response.text
        except requests.RequestException:
            continue

    raise RuntimeError(f"Failed to fetch HTML: {url}")


def fetch_text(url: str) -> str:
    sources = [
        (url, True),
        (f"https://api.allorigins.win/raw?url={quote(url, safe='')}", False),
        (build_jina_reader_url(url), False),
    ]

    for source, use_headers in sources:
        try:
            response = requests.get(
                source,
                timeout=25,
                headers={"User-Agent": "Mozilla/5.0"} if use_headers else None,
            )
            if response.status_code >= 400:
                continue
            if response.text:
                return response.text
        except requests.RequestException:
            continue

    raise RuntimeError(f"Failed to fetch: {url}")


def fetch_markdown(url: str) -> str:
    sources = [
        build_jina_reader_url(url),
        f"https://api.allorigins.win/raw?url={quote(url, safe='')}",
    ]

    for source in sources:
        try:
            response = requests.get(source, timeout=25)
            response.raise_for_status()
            if response.text:
                return response.text
        except requests.RequestException:
            continue

    raise RuntimeError(f"Failed to fetch markdown/text: {url}")


def get_soup(html: str) -> BeautifulSoup:
    return BeautifulSoup(html, "html.parser")


def strip_markdown_links(text: str) -> str:
    return re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)


def normalize_poetryfoundation_url(url: str) -> str:
    cleaned = re.sub(r"\s+", "", url)
    cleaned = cleaned.strip("\"'`.,;:!?)[]{}<>")
    cleaned = re.sub(r"^(https?://www\.poetryfoundation\.org)(?!/)", r"\1/", cleaned, flags=re.I)
    return cleaned


def is_poetryfoundation_poem_url(url: str) -> bool:
    lowered = url.lower()
    if "poem-of-the-day" in lowered:
        return False
    return bool(
        re.search(
            r"^https?://(?:www\.)?poetryfoundation\.org/(?:poems|poetrymagazine/poems)/\d+",
            url,
            flags=re.I,
        )
    )


def extract_poem_url_from_text(text: str) -> str:
    read_more_match = re.search(
        r"\[\s*Read\s+More\s*\]\(\s*(https?://.*?)\s*\)",
        text,
        flags=re.I | re.S,
    )
    if read_more_match:
        candidate = normalize_poetryfoundation_url(read_more_match.group(1))
        if is_poetryfoundation_poem_url(candidate):
            return candidate

    for match in re.finditer(r"\]\(\s*(https?://.*?)\s*\)", text, flags=re.I | re.S):
        candidate = normalize_poetryfoundation_url(match.group(1))
        if is_poetryfoundation_poem_url(candidate):
            return candidate

    poem_link_match = re.search(
        r"(https?://(?:www\.)?poetryfoundation\.org/(?:poems|poetrymagazine/poems)/\d+[^)\s]*)",
        text,
        flags=re.I,
    )
    if poem_link_match:
        candidate = normalize_poetryfoundation_url(poem_link_match.group(1))
        if is_poetryfoundation_poem_url(candidate):
            return candidate

    return POD_URL


def parse_markdown_page(text: str) -> dict:
    if "Markdown Content:" in text:
        text = text.split("Markdown Content:", 1)[1]

    lines = [strip_markdown_links(line.rstrip()) for line in text.splitlines()]

    title = ""
    for i in range(len(lines) - 1):
        if lines[i].strip() and set(lines[i + 1].strip()) == {"="}:
            title = lines[i].strip()
            break
    if " | " in title:
        title = title.split(" | ", 1)[0].strip()

    author = ""
    author_index = -1
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped == "By":
            next_non_empty = next((entry.strip() for entry in lines[i + 1 :] if entry.strip()), "")
            if next_non_empty:
                author = next_non_empty
                author_index = i + 1
                break
        if stripped.startswith("By "):
            author = stripped[3:].strip()
            author_index = i
            break

    stop_pattern = re.compile(
        r"^(Poems & Poets|Topics & Themes|Features|Grants & Programs|About Us|Poetry magazine|Subscribe|Related|More by|Advertise|Copyright|Source|Share|A note from the editor|Sign Up to Receive|RECENT POEMS OF THE DAY|Poetry Foundation Homepage)\b",
        re.I,
    )
    skip_inline = {"Share", "Play Audio"}
    poem_lines = []
    content_start = author_index + 1

    if author_index < 0:
        for i in range(len(lines) - 1):
            current = lines[i].strip()
            underline = lines[i + 1].strip()
            if current and underline and set(underline) in ({"="}, {"-"}):
                content_start = i + 2
                break

    for line in lines[content_start:]:
        stripped = line.strip()
        if not poem_lines and (not stripped or stripped in skip_inline):
            continue
        if stripped.startswith("[]("):
            continue
        if poem_lines and stop_pattern.match(stripped):
            break
        poem_lines.append(line)

    while poem_lines and not poem_lines[0].strip():
        poem_lines.pop(0)
    while poem_lines and not poem_lines[-1].strip():
        poem_lines.pop()

    poem = "\n".join(poem_lines)
    if title.lower() == "poem of the day" and not author:
        poem = ""

    return {
        "title": title,
        "author": author,
        "poem": poem,
    }


def is_valid_poem_content(data: dict) -> bool:
    poem = (data.get("poem") or "").strip()
    if not poem:
        return False

    title = (data.get("title") or "").strip().lower()
    author = (data.get("author") or "").strip()
    if title == "poem of the day" and not author:
        return False

    if len(poem) > 20000 or poem.count("\n") > 1200:
        return False

    blocked_tokens = (
        "window.__NUXT__",
        "primaryNavigation_Node",
        "cacheTags",
        "<script",
        "Poetry Foundation Homepage",
        "Sign Up to Receive the Poem of the Day",
    )
    return not any(token.lower() in poem.lower() for token in blocked_tokens)


def extract_poem_url(pod_soup: BeautifulSoup) -> str:
    pod_main = pod_soup.find("main") or pod_soup.body

    if pod_main:
        for link in pod_main.find_all("a"):
            if link.get_text(strip=True).lower() == "read more" and link.get("href"):
                href = link["href"]
                return f"{BASE_URL}{href}" if href.startswith("/") else href

        for link in pod_main.find_all("a", href=True):
            href = link["href"]
            if "/poems/" in href and "poem-of-the-day" not in href:
                return f"{BASE_URL}{href}" if href.startswith("/") else href

    return POD_URL


def main() -> None:
    pod_title = ""
    poem_url = POD_URL

    try:
        pod_html = fetch_html(POD_URL)
        pod_soup = get_soup(pod_html)
        if pod_soup.title and pod_soup.title.string:
            pod_title = pod_soup.title.string.split("|", 1)[0].strip()
        poem_url = extract_poem_url(pod_soup)
    except RuntimeError:
        pod_text = fetch_text(POD_URL)
        heading_match = re.search(r"^(.+?)\n=+", pod_text, flags=re.M)
        if heading_match:
            pod_title = strip_markdown_links(heading_match.group(1)).strip()
            if " | " in pod_title:
                pod_title = pod_title.split(" | ", 1)[0].strip()
        poem_url = extract_poem_url_from_text(pod_text)

    if poem_url == POD_URL:
        try:
            pod_text = fetch_markdown(POD_URL)
            poem_url = extract_poem_url_from_text(pod_text)
            if not pod_title:
                heading_match = re.search(r"^(.+?)\n=+", pod_text, flags=re.M)
                if heading_match:
                    pod_title = strip_markdown_links(heading_match.group(1)).strip()
                    if " | " in pod_title:
                        pod_title = pod_title.split(" | ", 1)[0].strip()
        except RuntimeError:
            pass

    poem_text_raw = ""
    data = {"title": "", "author": "", "poem": ""}
    try:
        poem_text_raw = fetch_text(poem_url)
        data = parse_markdown_page(poem_text_raw)
    except RuntimeError:
        pass

    if not is_valid_poem_content(data) or any(
        token in data.get("poem", "")
        for token in ("Poems & Poets", "Advertise", "PoetryMagazine")
    ):
        try:
            poem_text_raw = fetch_markdown(poem_url)
            data = parse_markdown_page(poem_text_raw)
        except RuntimeError:
            pass

    if (not data.get("poem")) and "<html" in poem_text_raw.lower():
        poem_soup = get_soup(poem_text_raw)
        main = poem_soup.find("main") or poem_soup.body

        title_el = main.find("h1") if main else None
        title = title_el.get_text(strip=True) if title_el else ""

        author = ""
        author_el = main.select_one("a[href*='/poets/']") if main else None
        if author_el:
            author = author_el.get_text(strip=True)
        if not author and main:
            by_el = next(
                (
                    el
                    for el in main.find_all(["p", "span", "div", "a"])
                    if (t := el.get_text(strip=True)) == "By" or t.startswith("By ")
                ),
                None,
            )
            if by_el:
                author = re.sub(r"^By\s+", "", by_el.get_text(strip=True))
                author = re.sub(r"Listen.*$", "", author, flags=re.I).strip()

        poem_el = (
            main.select_one(".o-poem__text, .c-poem__text, [data-testid='poem']")
            if main
            else None
        )
        poem_text = clean_text(poem_el.get_text("\n", strip=False)) if poem_el else ""

        if not poem_text and main:
            paragraphs = [
                p.get_text(strip=True)
                for p in main.find_all("p")
                if p.get_text(strip=True)
                and p.get_text(strip=True).lower() not in {"read more", "share", "share this"}
            ]
            poem_text = "\n\n".join(paragraphs)

        data = {
            "title": title,
            "author": author,
            "poem": poem_text,
        }

    if not is_valid_poem_content(data):
        data = {"title": "", "author": "", "poem": ""}

    if not data.get("title") and pod_title:
        data["title"] = pod_title

    if not data.get("poem"):
        if OUT_FILE.exists():
            try:
                existing = json.loads(OUT_FILE.read_text(encoding="utf-8"))
                if existing.get("poem"):
                    return
            except (json.JSONDecodeError, OSError):
                pass
        raise RuntimeError("Could not extract poem text; poem.json was not updated.")

    OUT_FILE.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
