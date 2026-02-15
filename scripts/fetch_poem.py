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
    lines = [line.strip().replace("\u00a0", " ") for line in text.splitlines()]
    return "\n".join([line for line in lines if line])


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
        if line.strip().startswith("By "):
            author = line.strip()[3:].strip()
            author_index = i
            break

    stop_pattern = re.compile(
        r"^(Poems & Poets|Topics & Themes|Features|Grants & Programs|About Us|Poetry magazine|Subscribe|Related|More by|Advertise|Copyright|Source|Share)\b",
        re.I,
    )
    skip_inline = {"Share", "Play Audio"}
    poem_lines = []

    if author_index >= 0:
        for line in lines[author_index + 1 :]:
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

    blank_count = sum(1 for line in poem_lines if not line.strip())
    if poem_lines and (blank_count / len(poem_lines)) > 0.3:
        cleaned = []
        for i, line in enumerate(poem_lines):
            if not line.strip():
                prev_non = i > 0 and poem_lines[i - 1].strip()
                next_non = i + 1 < len(poem_lines) and poem_lines[i + 1].strip()
                if prev_non and next_non:
                    continue
            cleaned.append(line)
        poem_lines = cleaned

    normalized = []
    last_blank = False
    for line in poem_lines:
        if line.strip():
            normalized.append(line)
            last_blank = False
        elif not last_blank:
            normalized.append("")
            last_blank = True

    while normalized and not normalized[0].strip():
        normalized.pop(0)
    while normalized and not normalized[-1].strip():
        normalized.pop()

    return {
        "title": title,
        "author": author,
        "poem": "\n".join(normalized).strip(),
    }


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
    pod_html = fetch_html(POD_URL)
    pod_soup = get_soup(pod_html)
    pod_title = ""
    if pod_soup.title and pod_soup.title.string:
        pod_title = pod_soup.title.string.split("|", 1)[0].strip()

    poem_url = extract_poem_url(pod_soup)

    poem_text_raw = ""
    data = {"title": "", "author": "", "poem": ""}
    try:
        poem_text_raw = fetch_text(poem_url)
        data = parse_markdown_page(poem_text_raw)
    except RuntimeError:
        pass

    if not data.get("poem") or any(
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
        poem_text = clean_text(poem_el.get_text("\n", strip=True)) if poem_el else ""

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

    if not data.get("title") and pod_title:
        data["title"] = pod_title

    if not data.get("poem"):
        raise RuntimeError("Could not extract poem text; poem.json was not updated.")

    OUT_FILE.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
