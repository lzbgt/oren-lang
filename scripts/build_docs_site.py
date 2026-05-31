#!/usr/bin/env python3
import argparse
import html
import json
import re
from pathlib import Path


DOCS = [
    ("Start Here", "docs/README.md", "start"),
    ("Status", "docs/STATUS.md", "status"),
    ("Tasks", "docs/BLEEDING_EDGE_TASKS.md", "tasks"),
    ("Language", "docs/LANGUAGE.md", "language"),
    ("Design", "docs/DESIGN.md", "design"),
    ("Readiness Tools", "docs/READINESS.md", "readiness"),
    ("Capabilities", "docs/CAPABILITY_RUNTIME_CONTRACT.md", "capabilities"),
    ("Effect Ledger", "docs/EFFECT_LEDGER_CONTRACT.md", "effect-ledger"),
    ("Gas Surface", "docs/GAS_SURFACE_REGISTRY.md", "gas-surface"),
    ("TODOs", "TODOS.md", "todos"),
    ("Project Notes", "project-doc/README.md", "project-notes"),
    ("Current Implementation", "project-doc/current_implementation_20260526.md", "current-implementation"),
    ("iOS AVM Readiness", "project-doc/ios_avm_readiness_20260507.md", "ios-avm-readiness"),
    ("iOS AVM SDK", "project-doc/ios_avm_sdk_design_20260531.md", "ios-avm-sdk"),
    ("AVM iOS Graphics", "project-doc/avm_ios_graphics_design_20260529.md", "avm-ios-graphics"),
    ("AVM UI Performance", "project-doc/avm_ui_render_performance_design_20260531.md", "avm-ui-performance"),
    ("OBC Store Distribution", "project-doc/obc_store_distribution_design_20260529.md", "obc-store-distribution"),
    ("Yield / Coroutine", "project-doc/yield_coroutine_lowering_20260422.md", "yield-coroutine"),
]


def slugify(text):
    slug = re.sub(r"[^a-zA-Z0-9]+", "-", text.strip().lower()).strip("-")
    return slug or "section"


def inline_md(text):
    text = html.escape(text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    return text


def render_markdown(src):
    lines = src.splitlines()
    out = []
    toc = []
    in_code = False
    code_lines = []
    in_ul = False
    in_ol = False
    in_table = False
    table_rows = []

    def close_lists():
        nonlocal in_ul, in_ol
        if in_ul:
            out.append("</ul>")
            in_ul = False
        if in_ol:
            out.append("</ol>")
            in_ol = False

    def close_table():
        nonlocal in_table, table_rows
        if not in_table:
            return
        out.append("<table>")
        for i, row in enumerate(table_rows):
            cells = [c.strip() for c in row.strip("|").split("|")]
            if i == 1 and all(re.fullmatch(r":?-{3,}:?", c) for c in cells):
                continue
            tag = "th" if i == 0 else "td"
            out.append("<tr>" + "".join(f"<{tag}>{inline_md(c)}</{tag}>" for c in cells) + "</tr>")
        out.append("</table>")
        in_table = False
        table_rows = []

    for raw in lines:
        line = raw.rstrip()
        if line.startswith("```"):
            close_table()
            close_lists()
            if in_code:
                out.append("<pre><code>" + html.escape("\n".join(code_lines)) + "</code></pre>")
                code_lines = []
                in_code = False
            else:
                in_code = True
            continue
        if in_code:
            code_lines.append(line)
            continue
        if "|" in line and line.strip().startswith("|") and line.strip().endswith("|"):
            close_lists()
            in_table = True
            table_rows.append(line)
            continue
        close_table()
        if not line.strip():
            close_lists()
            continue
        m = re.match(r"^(#{1,4})\s+(.+)$", line)
        if m:
            close_lists()
            level = len(m.group(1))
            text = m.group(2).strip()
            sid = slugify(text)
            toc.append({"level": level, "title": text, "id": sid})
            out.append(f'<h{level} id="{sid}">{inline_md(text)}</h{level}>')
            continue
        m = re.match(r"^\s*[-*]\s+(.+)$", line)
        if m:
            if in_ol:
                out.append("</ol>")
                in_ol = False
            if not in_ul:
                out.append("<ul>")
                in_ul = True
            out.append(f"<li>{inline_md(m.group(1))}</li>")
            continue
        m = re.match(r"^\s*\d+\.\s+(.+)$", line)
        if m:
            if in_ul:
                out.append("</ul>")
                in_ul = False
            if not in_ol:
                out.append("<ol>")
                in_ol = True
            out.append(f"<li>{inline_md(m.group(1))}</li>")
            continue
        close_lists()
        out.append(f"<p>{inline_md(line)}</p>")
    close_table()
    close_lists()
    if in_code:
        out.append("<pre><code>" + html.escape("\n".join(code_lines)) + "</code></pre>")
    return "\n".join(out), toc


def page_shell(title, body, nav, toc=None, search=True):
    toc = toc or []
    toc_html = "\n".join(
        f'<a class="toc-l{item["level"]}" href="#{item["id"]}">{html.escape(item["title"])}</a>'
        for item in toc if item["level"] <= 3
    )
    search_html = '<input id="searchBox" type="search" placeholder="Search docs..." autocomplete="off"><div id="searchResults"></div>' if search else ""
    rendered = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)} - Oren Docs</title>
  <link rel="stylesheet" href="../assets/site.css">
</head>
<body>
  <header class="topbar">
    <a class="brand" href="../index.html">Oren Docs</a>
    <button id="navToggle" aria-label="Toggle navigation">Menu</button>
  </header>
  <div class="layout">
    <nav id="sideNav" class="side">
      {search_html}
      {nav}
    </nav>
    <main class="content">
      {body}
    </main>
    <aside class="toc">
      <h2>On This Page</h2>
      {toc_html}
    </aside>
  </div>
  <script src="../assets/search-index.js"></script>
  <script src="../assets/site.js"></script>
</body>
</html>
"""
    return "\n".join(line.rstrip() for line in rendered.splitlines()) + "\n"


def write_assets(out_dir, search_index):
    assets = out_dir / "assets"
    assets.mkdir(parents=True, exist_ok=True)
    (assets / "search-index.js").write_text(
        "window.OREN_DOC_SEARCH_INDEX = " + json.dumps(search_index, ensure_ascii=False) + ";\n",
        encoding="utf-8",
    )
    (assets / "site.js").write_text(
        """const navToggle=document.getElementById('navToggle');
const sideNav=document.getElementById('sideNav');
if(navToggle&&sideNav){navToggle.addEventListener('click',()=>sideNav.classList.toggle('open'));}
const box=document.getElementById('searchBox');
const results=document.getElementById('searchResults');
if(box&&results&&window.OREN_DOC_SEARCH_INDEX){
  box.addEventListener('input',()=>{
    const q=box.value.trim().toLowerCase();
    results.innerHTML='';
    if(q.length<2)return;
    const hits=window.OREN_DOC_SEARCH_INDEX.filter(p=>(p.title+' '+p.text).toLowerCase().includes(q)).slice(0,8);
    for(const h of hits){
      const a=document.createElement('a');
      a.href=h.href;
      a.className='search-hit';
      a.textContent=h.title;
      results.appendChild(a);
    }
  });
}
""",
        encoding="utf-8",
    )
    (assets / "site.css").write_text(
        """:root{--bg:#f6f2ea;--paper:#fffdf7;--ink:#1d241f;--muted:#647067;--line:#d8d0c2;--accent:#0f6f5c;--accent2:#d56a2d;--code:#17211d}
*{box-sizing:border-box} body{margin:0;background:linear-gradient(135deg,#f6f2ea 0%,#eef6f2 45%,#fff8ec 100%);color:var(--ink);font:17px/1.58 Charter,Georgia,serif}
a{color:var(--accent);text-decoration:none} a:hover{text-decoration:underline}
.topbar{position:sticky;top:0;z-index:10;display:flex;align-items:center;justify-content:space-between;padding:12px 18px;background:rgba(255,253,247,.94);border-bottom:1px solid var(--line);backdrop-filter:blur(10px)}
.brand{font:800 19px/1.1 ui-serif,Georgia,serif;color:var(--ink)} #navToggle{display:none;border:1px solid var(--line);border-radius:999px;background:var(--paper);padding:8px 13px;color:var(--ink)}
.layout{display:grid;grid-template-columns:280px minmax(0,1fr) 240px;gap:24px;max-width:1480px;margin:0 auto;padding:24px}
.side,.toc{position:sticky;top:70px;align-self:start;max-height:calc(100vh - 90px);overflow:auto}
.side{background:rgba(255,253,247,.72);border:1px solid var(--line);border-radius:22px;padding:16px;box-shadow:0 18px 45px rgba(54,42,24,.07)}
.nav-group-title{margin:12px 0 6px;color:var(--muted);font:700 12px/1.2 ui-sans-serif,system-ui,sans-serif;text-transform:uppercase;letter-spacing:.08em}
.side a,.toc a{display:block;border-radius:12px;padding:7px 9px;color:var(--ink)}
.side a:hover,.toc a:hover{background:#e8f3ee;text-decoration:none}
#searchBox{width:100%;border:1px solid var(--line);border-radius:14px;padding:10px 12px;background:#fff;color:var(--ink);font:15px ui-sans-serif,system-ui,sans-serif}
#searchResults{margin:8px 0}.search-hit{font:14px ui-sans-serif,system-ui,sans-serif;background:#fff5e8;margin:3px 0}
.content{min-width:0;background:rgba(255,253,247,.88);border:1px solid var(--line);border-radius:28px;padding:34px;box-shadow:0 24px 65px rgba(54,42,24,.08)}
.content h1{font-size:42px;line-height:1.05;margin:0 0 18px}.content h2{font-size:27px;margin-top:34px;border-top:1px solid var(--line);padding-top:22px}.content h3{font-size:21px;margin-top:26px}
.content p,.content li{max-width:76ch}.content table{width:100%;border-collapse:collapse;display:block;overflow:auto}.content th,.content td{border:1px solid var(--line);padding:8px 10px;text-align:left}.content th{background:#edf6f1}
code{font:14px ui-monospace,SFMono-Regular,Menlo,monospace;background:#edf6f1;border-radius:6px;padding:1px 5px} pre{overflow:auto;border-radius:18px;background:var(--code);color:#f3f8f5;padding:16px} pre code{background:transparent;color:inherit;padding:0}
.toc{font:14px ui-sans-serif,system-ui,sans-serif;color:var(--muted)}.toc h2{font-size:12px;text-transform:uppercase;letter-spacing:.09em}.toc-l3{padding-left:18px!important;color:var(--muted)!important}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:14px}.card{display:block;border:1px solid var(--line);border-radius:20px;padding:18px;background:#fffdf7;min-height:112px}.card strong{display:block;color:var(--ink);font-size:18px}.card span{display:block;color:var(--muted);margin-top:8px}
@media(max-width:980px){#navToggle{display:block}.layout{display:block;padding:12px}.side{display:none;position:fixed;z-index:20;left:12px;right:12px;top:62px;max-height:75vh}.side.open{display:block}.content{padding:22px;border-radius:22px}.content h1{font-size:32px}.toc{display:none}}
""",
        encoding="utf-8",
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--out", default="docs/site")
    args = ap.parse_args()
    root = Path(args.root).resolve()
    out_dir = (root / args.out).resolve()
    pages_dir = out_dir / "pages"
    pages_dir.mkdir(parents=True, exist_ok=True)

    docs = []
    for title, rel, slug in DOCS:
        path = root / rel
        if not path.exists():
            continue
        src = path.read_text(encoding="utf-8")
        body, toc = render_markdown(src)
        docs.append({"title": title, "rel": rel, "slug": slug, "body": body, "toc": toc, "text": src})

    nav = '<div class="nav-group-title">Core</div>' + "\n".join(
        f'<a href="{ "../pages/" if False else ""}{d["slug"]}.html">{html.escape(d["title"])}</a>' for d in docs[:10]
    )
    nav += '<div class="nav-group-title">Project Notes</div>' + "\n".join(
        f'<a href="{d["slug"]}.html">{html.escape(d["title"])}</a>' for d in docs[10:]
    )
    page_nav = nav
    search_index = [{"title": d["title"], "href": f"{d['slug']}.html", "text": d["text"][:6000]} for d in docs]

    for d in docs:
        page = page_shell(d["title"], d["body"], page_nav, d["toc"])
        (pages_dir / f"{d['slug']}.html").write_text(page, encoding="utf-8")

    cards = "\n".join(
        f'<a class="card" href="pages/{d["slug"]}.html"><strong>{html.escape(d["title"])}</strong><span>{html.escape(d["rel"])}</span></a>'
        for d in docs
    )
    index_body = f"<h1>Oren Docs</h1><p>Responsive static documentation for desktop and iPhone. Generated from current Markdown sources.</p><div class=\"cards\">{cards}</div>"
    index_nav = '<div class="nav-group-title">Pages</div>' + "\n".join(
        f'<a href="pages/{d["slug"]}.html">{html.escape(d["title"])}</a>' for d in docs
    )
    index = page_shell("Index", index_body, index_nav, [], search=False).replace('../assets/', 'assets/').replace('../index.html', 'index.html')
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "index.html").write_text(index, encoding="utf-8")
    write_assets(out_dir, search_index)
    print(f"wrote {len(docs)} pages to {out_dir}")


if __name__ == "__main__":
    main()
