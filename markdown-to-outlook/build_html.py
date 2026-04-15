#!/usr/bin/env python3
"""
build_html.py
Converts final-architecture.md → final-architecture.html
  - Mermaid code blocks are rendered to inline SVG (default) or PNG (--use-png)
    via Playwright + headless Chromium (no Node.js required)
  - Markdown is converted to HTML via the `markdown` library
  - Output is a single self-contained HTML5 + CSS3 file

Setup:
    pip install -r requirements.txt
    playwright install chromium

Usage:
    python build_html.py
    python build_html.py --use-png
    python build_html.py --input my-doc.md --output my-doc.html --use-png
"""

import argparse
import base64
import re
import sys
import textwrap
from pathlib import Path

import markdown
from markdown.extensions.tables import TableExtension
from markdown.extensions.fenced_code import FencedCodeExtension
from playwright.sync_api import sync_playwright

# ---------------------------------------------------------------------------
# Configuration defaults
# ---------------------------------------------------------------------------
DEFAULT_INPUT  = Path(__file__).parent / "output.md"
DEFAULT_OUTPUT = Path(__file__).parent / "output.html"

MERMAID_THEME = "default"   # default | neutral | dark | forest
MERMAID_BG    = "white"     # background colour for diagrams
MERMAID_CDN   = "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"
MERMAID_SCALE = 3           # device-scale-factor for high-res PNG export

# ---------------------------------------------------------------------------
# CSS
# ---------------------------------------------------------------------------
CSS = """\
/* ── Reset & Base ── */
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

:root {
  --brand:      #0078D4;
  --brand-dark: #005A9E;
  --accent:     #40a9ff;
  --bg:         #f5f7fa;
  --surface:    #ffffff;
  --border:     #dde1e7;
  --text:       #1a1d23;
  --muted:      #6b7280;
  --radius:     8px;
  --shadow:     0 2px 8px rgba(0,0,0,.08);
  --font:       'Segoe UI', system-ui, -apple-system, sans-serif;
  --mono:       'Cascadia Code', 'Consolas', monospace;
}

html { scroll-behavior: smooth; }

body {
  font-family: var(--font);
  font-size: 15px;
  line-height: 1.7;
  color: var(--text);
  background: var(--bg);
}

/* ── Layout ── */
.page-wrap {
  display: flex;
  min-height: 100vh;
}

nav.toc {
  width: 260px;
  min-width: 260px;
  background: var(--surface);
  border-right: 1px solid var(--border);
  padding: 2rem 1.25rem;
  position: sticky;
  top: 0;
  height: 100vh;
  overflow-y: auto;
  font-size: 13px;
}

nav.toc .toc-title {
  font-size: 11px;
  font-weight: 700;
  letter-spacing: .08em;
  text-transform: uppercase;
  color: var(--muted);
  margin-bottom: 1rem;
}

nav.toc a {
  display: block;
  padding: .25rem .5rem;
  border-radius: 4px;
  text-decoration: none;
  color: var(--text);
  transition: background .15s, color .15s;
  line-height: 1.4;
}
nav.toc a:hover { background: var(--bg); color: var(--brand); }
nav.toc a.toc-h2 { font-weight: 600; margin-top: .5rem; }
nav.toc a.toc-h3 { padding-left: 1.25rem; color: var(--muted); font-size: 12px; }

main.content {
  flex: 1;
  padding: 3rem 4rem;
  max-width: 1400px;
}

@media (min-width: 1800px) {
  nav.toc     { width: 300px; min-width: 300px; }
  main.content { max-width: 1600px; padding: 3rem 5rem; }
}

@media (min-width: 2400px) {
  nav.toc     { width: 320px; min-width: 320px; font-size: 14px; }
  main.content { max-width: none; padding: 3rem 6rem; }
}

/* ── Typography ── */
h1 {
  font-size: 2rem;
  font-weight: 700;
  color: var(--brand-dark);
  border-bottom: 3px solid var(--brand);
  padding-bottom: .5rem;
  margin-bottom: .5rem;
}

h2 {
  font-size: 1.35rem;
  font-weight: 700;
  color: var(--brand-dark);
  border-bottom: 1px solid var(--border);
  padding-bottom: .3rem;
  margin: 2.5rem 0 1rem;
}

h3 {
  font-size: 1.1rem;
  font-weight: 600;
  color: var(--text);
  margin: 1.8rem 0 .6rem;
}

h4 {
  font-size: .95rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: .04em;
  color: var(--muted);
  margin: 1.2rem 0 .4rem;
}

p  { margin-bottom: .85rem; }
li { margin-bottom: .25rem; }
ul, ol { padding-left: 1.5rem; margin-bottom: .85rem; }

a { color: var(--brand); text-decoration: none; }
a:hover { text-decoration: underline; }

blockquote {
  border-left: 4px solid var(--accent);
  background: #f0f7ff;
  padding: .75rem 1.25rem;
  border-radius: 0 var(--radius) var(--radius) 0;
  margin: 1rem 0;
  color: var(--muted);
  font-size: .93rem;
}
blockquote p { margin: 0; }

code {
  font-family: var(--mono);
  font-size: .85em;
  background: #eef1f5;
  border: 1px solid var(--border);
  border-radius: 3px;
  padding: .1em .35em;
  color: #c7254e;
}

pre {
  background: #1e1e2e;
  border-radius: var(--radius);
  padding: 1.25rem 1.5rem;
  overflow-x: auto;
  margin-bottom: 1rem;
  box-shadow: var(--shadow);
}
pre code {
  background: none;
  border: none;
  padding: 0;
  color: #cdd6f4;
  font-size: .85rem;
}

/* ── Tables ── */
.table-wrap { overflow-x: auto; margin-bottom: 1.25rem; }

table {
  width: 100%;
  border-collapse: collapse;
  font-size: .9rem;
  background: var(--surface);
  border-radius: var(--radius);
  box-shadow: var(--shadow);
  overflow: hidden;
}

thead tr {
  background: var(--brand);
  color: #fff;
}
thead th {
  padding: .65rem 1rem;
  text-align: left;
  font-weight: 600;
  white-space: nowrap;
}

tbody tr { border-bottom: 1px solid var(--border); }
tbody tr:last-child { border-bottom: none; }
tbody tr:nth-child(even) { background: #f8fafc; }
tbody tr:hover { background: #eef5ff; }

td {
  padding: .55rem 1rem;
  vertical-align: top;
}

td strong { color: var(--brand-dark); }

/* ── Diagrams ── */
.diagram-wrap {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: 1.5rem;
  margin: 1.5rem 0;
  box-shadow: var(--shadow);
  overflow: hidden;
  text-align: center;
  position: relative;
}
.diagram-wrap.svg-interactive {
  cursor: pointer;
  transition: border-color .2s, box-shadow .2s;
}
.diagram-wrap.svg-interactive.active {
  cursor: grab;
  user-select: none;
  border-color: var(--brand);
  box-shadow: 0 0 0 3px rgba(0,120,212,.25), var(--shadow);
}
.diagram-wrap.svg-interactive.active.dragging {
  cursor: grabbing;
}
.diagram-wrap.svg-interactive .zoom-hint {
  position: absolute;
  top: .5rem;
  right: .5rem;
  font-size: .7rem;
  color: var(--muted);
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 4px;
  padding: .15rem .45rem;
  opacity: .7;
  pointer-events: none;
  transition: opacity .2s;
}
.diagram-wrap.svg-interactive:hover .zoom-hint { opacity: 1; }
.diagram-wrap svg {
  max-width: 100%;
  height: auto;
  transform-origin: 0 0;
}
.diagram-label {
  font-size: .78rem;
  color: var(--muted);
  text-align: center;
  margin-top: .5rem;
  font-style: italic;
}

/* ── Callout (blockquotes with bold Note:) ── */
blockquote:has(strong) {
  border-left-color: var(--brand);
  background: #f0f7ff;
}

/* ── Version badge ── */
.version-badge {
  display: inline-block;
  background: var(--brand);
  color: #fff;
  font-size: .72rem;
  font-weight: 700;
  letter-spacing: .06em;
  text-transform: uppercase;
  padding: .2rem .6rem;
  border-radius: 20px;
  margin-bottom: 1.5rem;
}

/* ── TOC mobile hide ── */
@media (max-width: 900px) {
  nav.toc { display: none; }
  main.content { padding: 2rem 1.5rem; }
  h1 { font-size: 1.5rem; }
}

/* ── Print ── */
@media print {
  nav.toc { display: none; }
  main.content { padding: 0; max-width: 100%; }
  body { background: #fff; font-size: 11pt; }
  .diagram-wrap { page-break-inside: avoid; }
}
"""

# ---------------------------------------------------------------------------
# Zoom & Pan JS (SVG mode only)
# ---------------------------------------------------------------------------
ZOOM_PAN_JS = """
<script>
(function() {
  var MIN_SCALE = 0.25, MAX_SCALE = 10, ZOOM_SPEED = 0.002;

  document.querySelectorAll('.diagram-wrap').forEach(function(wrap) {
    var svg = wrap.querySelector('svg');
    if (!svg) return;

    wrap.classList.add('svg-interactive');

    // add zoom hint badge
    var hint = document.createElement('span');
    hint.className = 'zoom-hint';
    hint.textContent = 'Click to interact';
    wrap.appendChild(hint);

    var scale = 1, tx = 0, ty = 0;
    var active = false;
    var dragging = false, startX = 0, startY = 0, startTx = 0, startTy = 0;

    function activate() {
      active = true;
      wrap.classList.add('active');
      hint.textContent = 'Scroll to zoom \u00b7 Drag to pan \u00b7 Dbl-click reset \u00b7 Esc to exit';
    }

    function deactivate() {
      active = false;
      dragging = false;
      wrap.classList.remove('active', 'dragging');
      hint.textContent = 'Click to interact';
    }

    function apply() {
      svg.style.transform = 'translate(' + tx + 'px,' + ty + 'px) scale(' + scale + ')';
    }

    // Click to activate
    wrap.addEventListener('click', function(e) {
      if (!active) { activate(); e.stopPropagation(); }
    });

    // Click outside or Esc to deactivate
    document.addEventListener('click', function(e) {
      if (active && !wrap.contains(e.target)) deactivate();
    });
    document.addEventListener('keydown', function(e) {
      if (active && e.key === 'Escape') deactivate();
    });

    // Wheel zoom — only when active
    wrap.addEventListener('wheel', function(e) {
      if (!active) return;  // let page scroll through
      e.preventDefault();
      var rect = wrap.getBoundingClientRect();
      var mx = e.clientX - rect.left;
      var my = e.clientY - rect.top;

      var delta = -e.deltaY * ZOOM_SPEED;
      var newScale = Math.min(MAX_SCALE, Math.max(MIN_SCALE, scale * (1 + delta)));
      var factor = newScale / scale;

      tx = mx - factor * (mx - tx);
      ty = my - factor * (my - ty);
      scale = newScale;
      apply();
    }, { passive: false });

    // Drag pan — only when active
    wrap.addEventListener('mousedown', function(e) {
      if (!active || e.button !== 0) return;
      dragging = true;
      startX = e.clientX; startY = e.clientY;
      startTx = tx; startTy = ty;
      wrap.classList.add('dragging');
      e.preventDefault();
    });
    window.addEventListener('mousemove', function(e) {
      if (!dragging) return;
      tx = startTx + (e.clientX - startX);
      ty = startTy + (e.clientY - startY);
      apply();
    });
    window.addEventListener('mouseup', function() {
      if (!dragging) return;
      dragging = false;
      wrap.classList.remove('dragging');
    });

    // Double-click reset — only when active
    wrap.addEventListener('dblclick', function() {
      if (!active) return;
      scale = 1; tx = 0; ty = 0;
      apply();
    });
  });
})();
</script>
"""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def extract_mermaid_blocks(md_text: str):
    """
    Returns (cleaned_md, list_of_mermaid_src_strings).
    Replaces each ```mermaid ... ``` block with a unique placeholder.
    """
    pattern = re.compile(r"```mermaid\s*\n(.*?)```", re.DOTALL)
    blocks = []
    counter = [0]

    def replacer(m):
        idx = counter[0]
        counter[0] += 1
        blocks.append(m.group(1).strip())
        return f"\n\n<!-- MERMAID_BLOCK_{idx} -->\n\n"

    cleaned = pattern.sub(replacer, md_text)
    return cleaned, blocks


class MermaidRenderer:
    """Renders Mermaid diagrams via Playwright + headless Chromium (no Node.js)."""

    def __init__(self, theme: str = "default", bg: str = "white", scale: int = 3):
        self.theme = theme
        self.bg = bg
        self.scale = scale
        self._pw = None
        self._browser = None
        self._page = None

    def __enter__(self):
        self._pw = sync_playwright().start()
        self._browser = self._pw.chromium.launch()
        ctx = self._browser.new_context(
            viewport={"width": 1600, "height": 900},
            device_scale_factor=self.scale,
        )
        self._page = ctx.new_page()
        self._page.set_content(
            f'<!DOCTYPE html><html><head>'
            f'<script src="{MERMAID_CDN}"></script>'
            f'</head><body style="background:{self.bg};margin:0">'
            f'<div id="container"></div>'
            f'<script>mermaid.initialize({{startOnLoad:false,theme:"{self.theme}"}});</script>'
            f'</body></html>',
            wait_until="networkidle",
        )
        self._page.wait_for_function(
            "typeof mermaid !== 'undefined' && typeof mermaid.render === 'function'"
        )
        return self

    def __exit__(self, *exc):
        if self._browser:
            self._browser.close()
        if self._pw:
            self._pw.stop()

    def render_svg(self, mermaid_src: str) -> str:
        """Return an SVG string for the given Mermaid source."""
        assert self._page is not None, "Call render_svg inside a 'with' block"
        try:
            svg = self._page.evaluate(
                """async (src) => {
                    const id = 'dia_' + Math.random().toString(36).slice(2);
                    const { svg } = await mermaid.render(id, src);
                    return svg;
                }""",
                mermaid_src,
            )
            return svg
        except Exception as e:
            print(f"  [WARN] Mermaid render error: {e}", file=sys.stderr)
            return f'<pre style="color:red">Mermaid render failed:\n{e}</pre>'

    def render_png_b64(self, mermaid_src: str) -> str:
        """Return a base64-encoded high-res PNG for the given Mermaid source."""
        assert self._page is not None, "Call render_png_b64 inside a 'with' block"
        svg = self.render_svg(mermaid_src)
        if svg.startswith("<pre"):
            return ""
        try:
            self._page.evaluate(
                "(svg) => { document.getElementById('container').innerHTML = svg; }",
                svg,
            )
            el = self._page.query_selector("#container svg")
            assert el is not None, "SVG element not found after injection"
            png_bytes = el.screenshot(type="png")
            return base64.b64encode(png_bytes).decode("ascii")
        except Exception as e:
            print(f"  [WARN] PNG screenshot error: {e}", file=sys.stderr)
            return ""


def svg_to_inline(svg_text: str, label: str = "") -> str:
    """
    Strips the XML declaration and wraps SVG in a .diagram-wrap div.
    Also removes fixed width/height so the SVG is responsive.
    """
    # Remove XML declaration
    svg_text = re.sub(r"<\?xml[^>]*\?>", "", svg_text).strip()
    # Remove hard-coded width/height attributes on the <svg> tag so CSS controls sizing
    svg_text = re.sub(r'(<svg[^>]*?) width="[^"]*"', r"\1", svg_text)
    svg_text = re.sub(r'(<svg[^>]*?) height="[^"]*"', r"\1", svg_text)
    label_html = f'<p class="diagram-label">{label}</p>' if label else ""
    return f'<div class="diagram-wrap">\n{svg_text}\n{label_html}</div>'


def png_to_inline(b64_data: str, label: str = "") -> str:
    """Wraps a base64-encoded PNG as a responsive <img> inside .diagram-wrap."""
    if not b64_data:
        return '<div class="diagram-wrap"><p style="color:red">PNG render failed</p></div>'
    label_html = f'<p class="diagram-label">{label}</p>' if label else ""
    img = (
        f'<img src="data:image/png;base64,{b64_data}" '
        f'alt="{label}" style="max-width:100%;height:auto;">'
    )
    return f'<div class="diagram-wrap">\n{img}\n{label_html}</div>'


def wrap_tables(html: str) -> str:
    """Wrap every <table> in a scrollable .table-wrap div."""
    return re.sub(r"(<table)", r'<div class="table-wrap">\1', html).replace(
        "</table>", "</table></div>"
    )


def build_toc(html: str) -> tuple[str, str]:
    """
    Scans h2/h3 tags in the HTML and builds a sticky sidebar TOC.
    Also injects id attributes on headings if missing.
    """
    heading_re = re.compile(r"<(h[23])([^>]*)>(.*?)</h[23]>", re.IGNORECASE | re.DOTALL)

    toc_items = []
    used_ids: dict[str, int] = {}

    def inject_id(m):
        tag   = m.group(1).lower()
        attrs = m.group(2)
        inner = m.group(3)
        # strip any inline HTML for the slug
        text  = re.sub(r"<[^>]+>", "", inner).strip()

        # If the heading already has an id (e.g. from the markdown toc extension),
        # use that id for the TOC link instead of generating a new slug.
        existing = re.search(r'id="([^"]+)"', attrs)
        if existing:
            slug = existing.group(1)
        else:
            slug = re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")
            # deduplicate
            if slug in used_ids:
                used_ids[slug] += 1
                slug = f"{slug}_{used_ids[slug]}"
            else:
                used_ids[slug] = 0
            attrs = f' id="{slug}"' + attrs

        toc_class = "toc-h2" if tag == "h2" else "toc-h3"
        toc_items.append((toc_class, slug, text))
        return f"<{tag}{attrs}>{inner}</{tag}>"

    enriched_html = heading_re.sub(inject_id, html)

    toc_lines = ['<nav class="toc"><div class="toc-title">Contents</div>']
    for css_class, anchor, text in toc_items:
        short = text[:60] + ("…" if len(text) > 60 else "")
        toc_lines.append(f'<a href="#{anchor}" class="{css_class}">{short}</a>')
    toc_lines.append("</nav>")

    return "\n".join(toc_lines), enriched_html


def md_to_html_body(md_text: str) -> str:
    """Convert markdown to HTML using python-markdown with useful extensions."""
    md = markdown.Markdown(
        extensions=[
            "tables",
            "fenced_code",
            "toc",
            "attr_list",
            "def_list",
            "md_in_html",
            "pymdownx.highlight",
            "pymdownx.superfences",
        ],
        extension_configs={
            "pymdownx.highlight": {"use_pygments": False},
        },
    )
    return md.convert(md_text)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def build(input_path: Path, output_path: Path, use_png: bool = False):
    mode = "PNG" if use_png else "SVG"
    print(f"Reading  : {input_path}  [diagram mode: {mode}]")
    md_text = input_path.read_text(encoding="utf-8")

    # ── 1. Extract mermaid blocks ──────────────────────────────────────────
    print("Extracting mermaid blocks…")
    md_clean, mermaid_blocks = extract_mermaid_blocks(md_text)
    print(f"  Found {len(mermaid_blocks)} diagram(s)")

    # ── 2. Render each mermaid block ───────────────────────────────────────
    svg_replacements = {}
    diagram_labels = [
        "Architecture Overview",
        "Integration Pattern",
        "Rollout & Migration Strategy",
        "Diagram 4", "Diagram 5",  # fallbacks
    ]
    if mermaid_blocks:
        print("  Launching headless Chromium…")
        with MermaidRenderer(theme=MERMAID_THEME, bg=MERMAID_BG, scale=MERMAID_SCALE) as renderer:
            for i, src in enumerate(mermaid_blocks):
                label = diagram_labels[i] if i < len(diagram_labels) else f"Diagram {i+1}"
                print(f"  Rendering diagram {i+1}/{len(mermaid_blocks)}: {label} ({mode})…")
                if use_png:
                    b64 = renderer.render_png_b64(src)
                    svg_replacements[f"<!-- MERMAID_BLOCK_{i} -->"] = png_to_inline(b64, label)
                else:
                    svg_text = renderer.render_svg(src)
                    svg_replacements[f"<!-- MERMAID_BLOCK_{i} -->"] = svg_to_inline(svg_text, label)

    # ── 3. Convert markdown to HTML ────────────────────────────────────────
    print("Converting markdown → HTML…")
    body_html = md_to_html_body(md_clean)

    # ── 4. Inject SVGs back in ─────────────────────────────────────────────
    for placeholder, svg_div in svg_replacements.items():
        # markdown may wrap the comment in a <p> or leave it bare
        body_html = body_html.replace(f"<p>{placeholder}</p>", svg_div)
        body_html = body_html.replace(placeholder, svg_div)

    # ── 5. Wrap tables ─────────────────────────────────────────────────────
    body_html = wrap_tables(body_html)

    # ── 6. Build TOC ───────────────────────────────────────────────────────
    toc_html, body_html = build_toc(body_html)

    # ── 7. Extract title from first <h1> ───────────────────────────────────
    title_match = re.search(r"<h1[^>]*>(.*?)</h1>", body_html, re.IGNORECASE | re.DOTALL)
    title = re.sub(r"<[^>]+>", "", title_match.group(1)).strip() if title_match else "Architecture"

    # ── 8. Assemble final HTML ─────────────────────────────────────────────
    zoom_js = ""
    if not use_png:
        zoom_js = ZOOM_PAN_JS

    html = textwrap.dedent(f"""\
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>{title}</title>
      <style>
    {CSS}
      </style>
    </head>
    <body>
      <div class="page-wrap">
        {toc_html}
        <main class="content">
    {body_html}
        </main>
      </div>{zoom_js}
    </body>
    </html>
    """)

    output_path.write_text(html, encoding="utf-8")
    size_kb = output_path.stat().st_size / 1024
    print(f"Written  : {output_path}  ({size_kb:.0f} KB)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert an architecture .md to a self-contained .html")
    parser.add_argument("-i", "--input",   default=str(DEFAULT_INPUT),  help="Source markdown file")
    parser.add_argument("-o", "--output",  default=str(DEFAULT_OUTPUT), help="Output HTML file")
    parser.add_argument("--use-png", action="store_true",
                        help="Embed diagrams as high-resolution PNG instead of inline SVG")
    parser.add_argument("--both", action="store_true",
                        help="Export both SVG and PNG versions (ignores --output, derives names from --input)")
    args = parser.parse_args()

    if args.both:
        base = Path(args.input).stem
        out_dir = Path(args.input).parent
        svg_out = out_dir / f"{base}.html"
        png_out = out_dir / f"{base}-png.html"
        build(Path(args.input), svg_out, use_png=False)
        build(Path(args.input), png_out, use_png=True)
    else:
        build(Path(args.input), Path(args.output), use_png=args.use_png)
