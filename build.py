#!/usr/bin/env python3
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
JOKES = ROOT / "jokes"
INDEX = ROOT / "joke.md"
SECTION = re.compile(r"^## (\d+)\s*$", re.M)


def sections(text):
    found = list(SECTION.finditer(text))
    for i, match in enumerate(found):
        end = found[i + 1].start() if i + 1 < len(found) else len(text)
        yield match.group(1), text[match.start():end].strip() + "\n"


def migrate():
    if not INDEX.exists():
        return
    known = {p.stem for p in JOKES.glob("*.md") if p.stem.isdigit()}
    for number, body in sections(INDEX.read_text(encoding="utf-8")):
        if number in known:
            continue
        (JOKES / f"{number}.md").write_text(body, encoding="utf-8")
        known.add(number)
        print(f"migrated ## {number}")


def build():
    files = sorted(
        (p for p in JOKES.glob("*.md") if p.stem.isdigit()),
        key=lambda p: int(p.stem),
    )
    body = "\n".join(p.read_text(encoding="utf-8").strip() + "\n" for p in files)
    INDEX.write_text("# 段子集\n\n" + body, encoding="utf-8")


def main():
    JOKES.mkdir(exist_ok=True)
    migrate()
    build()


if __name__ == "__main__":
    sys.exit(main())
