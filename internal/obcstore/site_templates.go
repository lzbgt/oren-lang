package obcstore

import (
	"html/template"
	"net/http"
)

var (
	siteHomeTemplate      = template.Must(template.New("store-home").Parse(siteHomeHTML))
	sitePackageTemplate   = template.Must(template.New("store-package").Parse(sitePackageHTML))
	sitePublisherTemplate = template.Must(template.New("store-publisher").Parse(sitePublisherHTML))
	siteOpsTemplate       = template.Must(template.New("store-ops").Parse(siteOpsHTML))
	siteOpsStatusTemplate = template.Must(template.New("store-ops-status").Parse(siteOpsStatusHTML))
)

func renderHTML(w http.ResponseWriter, tmpl *template.Template, data any) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_ = tmpl.Execute(w, data)
}

const siteCSS = `
body{margin:0;background:#f5f1e8;color:#1c1913;font:16px/1.5 Georgia,"Times New Roman",serif}
a{color:#146c5b;text-decoration:none}a:hover{text-decoration:underline}
header{background:linear-gradient(135deg,#17211f,#36584d);color:#fff;padding:36px 22px}
main{max-width:980px;margin:0 auto;padding:24px}
.brand{font-size:38px;letter-spacing:-1px;margin:0 0 8px}
.muted{color:#675f50}.pill{display:inline-block;border:1px solid #d7cdbb;border-radius:999px;padding:2px 9px;margin:2px;background:#fff8ec}
.card{background:#fffaf0;border:1px solid #ded3bd;border-radius:18px;padding:18px;margin:14px 0;box-shadow:0 8px 24px #00000012}
input{font:inherit;padding:10px;border:1px solid #cbbfa8;border-radius:10px;background:#fff}
button{font:inherit;padding:10px 14px;border:0;border-radius:10px;background:#146c5b;color:white}
code,pre{background:#eee3d0;border-radius:8px;padding:2px 5px}pre{overflow:auto;padding:14px}
table{width:100%;border-collapse:collapse}td,th{border-bottom:1px solid #e2d7c3;padding:8px;text-align:left}
@media(max-width:680px){.brand{font-size:30px}main{padding:16px}input,button{width:100%;margin-top:8px}}
`

const siteHomeHTML = `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>OBC Store</title><style>` + siteCSS + `</style></head>
	<body><header><h1 class="brand">OBC Store</h1><p>Public Oren bytecode packages for AVM host apps.</p></header>
<main>
<form class="card" action="/" method="get">
  <input name="query" placeholder="Search packages" value="{{.Query}}">
  <input name="tag" placeholder="Tag" value="{{.Tag}}">
  <input name="capability" placeholder="Capability, e.g. GFX" value="{{.Capability}}">
  <button type="submit">Search</button>
</form>
<p><a href="/api/v0/index.json">index.json</a> · <a href="/api/v0/trust/bundle.json">trust bundle</a> · <a href="/ops">operator guide</a> · <a href="/ops/status">operator status</a></p>
{{if .Packages}}{{range .Packages}}
<article class="card">
	  <h2><a href="/packages/{{.Publisher}}/{{.Name}}">{{if .Title}}{{.Title}}{{else}}{{.ID}}{{end}}</a></h2>
	  <p class="muted"><a href="/publishers/{{.Publisher}}">{{.Publisher}}</a>/{{.Name}}@{{.Version}}</p>
  <p>{{.Summary}}</p>
  <p>{{range .Tags}}<span class="pill">{{.}}</span>{{end}}</p>
</article>
{{end}}{{else}}<div class="card">No published OBC packages match this query.</div>{{end}}
</main></body></html>`

const sitePackageHTML = `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{{.Meta.Publisher}}/{{.Meta.Name}} - OBC Store</title><style>` + siteCSS + `</style></head>
<body><header><h1 class="brand">{{if .Meta.Title}}{{.Meta.Title}}{{else}}{{.Meta.Publisher}}/{{.Meta.Name}}{{end}}</h1><p>{{.Meta.Summary}}</p></header>
<main>
<p><a href="/">Browse packages</a> · <a href="/publishers/{{.Meta.Publisher}}">Publisher: {{.Meta.Publisher}}</a></p>
<section class="card">
  <h2>Releases</h2>
  {{if .Releases}}<table><tr><th>Version</th><th>Manifest</th><th>Program</th><th>Bundle</th><th>Capabilities</th><th>Source</th><th>Permissions</th><th>Status</th></tr>
	  {{range .Releases}}<tr>
	    <td>{{.Version}}</td>
	    <td><a href="/api/v0/packages/{{.Publisher}}/{{.Name}}/versions/{{.Version}}/package.json">package.json</a></td>
	    <td><a href="/api/v0/packages/{{.Publisher}}/{{.Name}}/versions/{{.Version}}/program.obc">program.obc</a></td>
	    <td>{{if .BundlePath}}<a href="/api/v0/packages/{{.Publisher}}/{{.Name}}/versions/{{.Version}}/bundle.obc.zip">bundle.obc.zip</a>{{else}}-{{end}}</td>
	    <td>{{range .Capabilities}}<span class="pill">{{.}}</span>{{else}}-{{end}}</td>
	    <td>{{range .Sources}}<a href="{{.URL}}">{{if .Role}}{{.Role}}{{else}}{{.Path}}{{end}}</a> {{else}}-{{end}}</td>
	    <td>{{if .PermissionDefaultsCount}}{{.PermissionDefaultsCount}} default(s){{else}}-{{end}}</td>
	    <td>{{.Status}}</td>
	  </tr>{{end}}</table>{{else}}No published releases.{{end}}
</section>
<section class="card"><h2>Install Metadata</h2><pre>package={{.Meta.Publisher}}/{{.Meta.Name}}
index=https://store.hubstack.cn/api/v0/index.json</pre></section>
</main></body></html>`

const sitePublisherHTML = `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{{.Publisher.ID}} - OBC Store</title><style>` + siteCSS + `</style></head>
<body><header><h1 class="brand">{{if .Publisher.DisplayName}}{{.Publisher.DisplayName}}{{else}}{{.Publisher.ID}}{{end}}</h1><p>Public packages by {{.Publisher.ID}}.</p></header>
<main>
<p><a href="/">Browse packages</a> · <a href="/ops">operator guide</a> · <a href="/ops/status">operator status</a></p>
{{if .Packages}}{{range .Packages}}
<article class="card">
  <h2><a href="/packages/{{.Publisher}}/{{.Name}}">{{if .Title}}{{.Title}}{{else}}{{.ID}}{{end}}</a></h2>
  <p class="muted">{{.ID}}@{{.Version}}</p>
  <p>{{.Summary}}</p>
  <p>{{range .Tags}}<span class="pill">{{.}}</span>{{end}}</p>
</article>
{{end}}{{else}}<div class="card">No public packages are currently published for this publisher.</div>{{end}}
</main></body></html>`

const siteOpsHTML = `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>OBC Store Operator Guide</title><style>` + siteCSS + `</style></head>
<body><header><h1 class="brand">Operator Guide</h1><p>Minimal publish and token lifecycle reference.</p></header>
<main>
<section class="card"><h2>Deployment status</h2><p><a href="/ops/status">Authenticated operator status page</a> · <code>GET /api/v0/ops/status</code></p></section>
<section class="card"><h2>Public endpoints</h2><pre>GET /healthz
GET /api/v0/health
GET /api/v0/index.json
	GET /api/v0/index.json.sig
	GET /api/v0/packages?query=plot&amp;capability=GFX</pre>
	<p>Packages are public by default. Private packages are omitted from public browse/search/index/download surfaces.</p></section>
<section class="card"><h2>Publisher token lifecycle</h2><pre>POST   /api/v0/publishers/{publisher}/token
DELETE /api/v0/publishers/{publisher}/token
Authorization: Bearer &lt;current publisher token or admin token&gt;
Body: {"token_sha256_hex":"&lt;sha256 hex of new token&gt;"}</pre></section>
	<section class="card"><h2>Publish flow</h2><pre>POST /api/v0/packages
	POST /api/v0/packages/{publisher}/{name}/versions
	POST /api/v0/packages/{publisher}/{name}/versions/{version}/publish
	POST /api/v0/packages/{publisher}/{name}/visibility
	Body: {"visibility":"public|private"}</pre>
	<p>Release uploads may include release_bundle_base64 for deterministic .obc.zip bundles.</p></section>
</main></body></html>`

const siteOpsStatusHTML = `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>OBC Store Operator Status</title><style>` + siteCSS + `</style></head>
<body><header><h1 class="brand">Operator Status</h1><p>Authenticated deployment summary for store.hubstack.cn.</p></header>
<main>
<p><a href="/">Browse packages</a> · <a href="/ops">operator guide</a> · <a href="/api/v0/ops/status">status JSON</a></p>
<section class="card"><h2>Registry Counts</h2><table>
<tr><th>Publishers</th><td>{{.PublisherCount}} total, {{.ActivePublisherCount}} active, {{.DisabledPublisherCount}} disabled</td></tr>
<tr><th>Packages</th><td>{{.PackageCount}} total, {{.PublicPackageCount}} public, {{.PrivatePackageCount}} private</td></tr>
<tr><th>Releases</th><td>{{.ReleaseCount}} total, {{.PublishedReleaseCount}} published, {{.YankedReleaseCount}} yanked, {{.DraftReleaseCount}} draft</td></tr>
</table></section>
<section class="card"><h2>Release Readiness</h2><table>
<tr><th>Bundles</th><td>{{.BundleReleaseCount}} release(s)</td></tr>
<tr><th>Publisher signatures</th><td>{{.SignedReleaseCount}} release(s)</td></tr>
<tr><th>Source metadata</th><td>{{.SourceReleaseCount}} release(s), {{.SourceAssetCount}} linked source asset(s)</td></tr>
<tr><th>Permission defaults</th><td>{{.PermissionDefaultCount}} default grant record(s)</td></tr>
</table></section>
<section class="card"><h2>Deployment Gates</h2><table>
<tr><th>Signed index</th><td>{{.SignedIndexEnabled}}</td></tr>
<tr><th>Trust bundle</th><td>{{.TrustBundleAvailable}}</td></tr>
<tr><th>Admin auth</th><td>{{.AdminAuthConfigured}}</td></tr>
<tr><th>Generated at</th><td>{{.GeneratedAt}}</td></tr>
</table></section>
<section class="card"><h2>Smoke Commands</h2><pre>curl -fsS https://store.hubstack.cn/healthz
curl -fsS https://store.hubstack.cn/api/v0/index.json
curl -fsS -u "$OBC_STORE_ADMIN_USERNAME:$OBC_STORE_ADMIN_PASSWORD" https://store.hubstack.cn/api/v0/ops/status</pre></section>
</main></body></html>`
