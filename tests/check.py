"""Integration check for HTML carousels and the PDF fallback.

Run with: python3 tests/check.py
Requires Quarto with Typst; checks PDF text too if pdftotext is installed.
"""
from html.parser import HTMLParser
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


class CarouselHTML(HTMLParser):
    def __init__(self):
        super().__init__()
        self.counts = dict(carousels=0, slides=0, indicators=0, controls=0, images=0)
        self.sources = []
        self.identifiers = set()
        self.references = []
        self.in_reference = False

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        classes = attrs.get("class", "").split()
        if "id" in attrs:
            self.identifiers.add(attrs["id"])
        if tag == "a" and "quarto-xref" in classes:
            self.references.append([attrs.get("href"), ""])
            self.in_reference = True
        self.counts["carousels"] += "carousel" in classes
        self.counts["slides"] += "carousel-item" in classes
        self.counts["indicators"] += tag == "button" and "data-bs-slide-to" in attrs
        self.counts["controls"] += tag == "button" and "data-bs-slide" in attrs
        source = attrs.get("src", "")
        if tag == "img" and "assets/" in source:
            self.counts["images"] += 1
            self.sources.append(source)


    def handle_data(self, text):
        if self.in_reference:
            self.references[-1][1] += text

    def handle_endtag(self, tag):
        if tag == "a":
            self.in_reference = False


with tempfile.TemporaryDirectory(prefix="carousel-test-") as directory:
    project = Path(directory)
    for folder in ("_extensions", "assets", "tests"):
        shutil.copytree(ROOT / folder, project / folder)
    for file in ("_quarto.yml", "example.qmd"):
        shutil.copy2(ROOT / file, project / file)
    # Exercise SVG inclusion without adding image assets to the repository.
    (project / "assets/test-image.svg").write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 400">'
        '<rect width="1200" height="400" fill="#336699"/></svg>'
    )
    # Keep format and syntax regression cases separate from the public demo.
    (project / "check.qmd").write_text("""---
format:
  html: default
  typst: default
filters:
  - carousel
  - tests/static.lua
---

::::: {.carousel .dark .framed autoplay="false"}
:::: {.item image="assets/test-image.svg" caption="Step 1: visit Rosario.<br>Cross the river."}
Slide body.
::::
:::: {.item image="assets/imgs/bariloche_emilio-lujan_cropped.jpg" caption="Step 2: visit Bariloche.<br><strong>Lake and mountains.</strong>"}
::::
:::::

::::: {.carousel .dark .framed autoplay="false"}
:::: {.carousel-item image="assets/test-image.svg" caption="Visit Rosario."}
::::
:::: {.carousel-item image="assets/imgs/bariloche_emilio-lujan_cropped.jpg" caption="Continue to Bariloche."}
::::
:::::

::: {.carousel .dark .framed autoplay="false"}
![Markdown image: the bridge in Rosario.](assets/test-image.svg)

![The lake in Bariloche.](assets/imgs/bariloche_emilio-lujan_cropped.jpg){#fig-bariloche}
:::

See @fig-bariloche for the lake in Bariloche.
""")
    config = project / "_quarto.yml"
    config.write_text(config.read_text() + "    - check.qmd\n")
    env = os.environ.copy()
    env["XDG_CACHE_HOME"] = str(project / "cache")
    rendered = subprocess.run(
        ["quarto", "render"], cwd=project, env=env, check=True,
        capture_output=True, text=True,
    )
    print(rendered.stdout, end="")
    print(rendered.stderr, end="")
    assert "Unable to resolve crossref" not in rendered.stderr
    output = project / "_site"
    html = (output / "check.html").read_text()
    parsed = CarouselHTML()
    parsed.feed(html)
    assert parsed.counts == dict(carousels=3, slides=6, indicators=6, controls=6, images=6), parsed.counts
    assert "fig-bariloche" in parsed.identifiers, "Figure target was discarded"
    assert any(href == "#fig-bariloche" and re.fullmatch(r"Figure\s+\d+", text)
               for href, text in parsed.references), parsed.references
    for source in parsed.sources:
        assert (output / source).is_file(), f"Missing resource: {source}"
    assert (output / "example.pdf").stat().st_size > 0
    assert (output / "check.pdf").stat().st_size > 0
    if shutil.which("pdftotext"):
        text = subprocess.check_output(["pdftotext", str(output / "check.pdf"), "-"], text=True)
        normalized = " ".join(text.split())
        reference = re.search(r"See Figure (\d+) for the lake in Bariloche", normalized)
        assert reference, "PDF figure reference was not resolved"
        assert f"Figure {reference[1]}: The lake in Bariloche." in normalized
        captions = [
            "Step 1: visit Rosario.", "Cross the river.", "Slide body.",
            "Step 2: visit Bariloche.", "Lake and mountains.",
            "Visit Rosario.", "Continue to Bariloche.",
            "Markdown image: the bridge in Rosario.",
            "The lake in Bariloche.",
        ]
        position = 0
        for caption in captions:
            position = text.index(caption, position) + len(caption)
    print("PASS: HTML, Typst PDF, native AST, captions, figure references, ordering and site resources")
