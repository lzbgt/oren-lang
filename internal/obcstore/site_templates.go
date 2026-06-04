package obcstore

import (
	"html/template"
	"net/http"
)

var (
	siteHomeTemplate        = template.Must(template.New("store-home").Parse(siteHomeHTML))
	sitePackageTemplate     = template.Must(template.New("store-package").Parse(sitePackageHTML))
	sitePublisherTemplate   = template.Must(template.New("store-publisher").Parse(sitePublisherHTML))
	siteSourceTemplate      = template.Must(template.New("store-source").Parse(siteSourceHTML))
	siteOpsTemplate         = template.Must(template.New("store-ops").Parse(siteOpsHTML))
	siteOpsStatusTemplate   = template.Must(template.New("store-ops-status").Parse(siteOpsStatusHTML))
	siteOpsReleasesTemplate = template.Must(template.New("store-ops-releases").Parse(siteOpsReleasesHTML))
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
	.package-card{display:grid;grid-template-columns:minmax(0,1fr) 220px;gap:18px;align-items:center}
	.preview{width:100%;max-width:360px;border-radius:14px;border:1px solid #d7cdbb;background:#17211f;box-shadow:0 10px 24px #0000001a}
	.source-layout{display:grid;grid-template-columns:240px minmax(0,1fr);gap:18px;align-items:start}
	.source-code{margin:0;background:#102820;color:#f5efe0;border-radius:14px;padding:16px;overflow:auto;font:14px/1.55 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
	.source-line{white-space:pre}.ln{display:inline-block;width:4ch;color:#8aa399;text-align:right;margin-right:12px;user-select:none}
	.tok-keyword{color:#8fd7ff;font-weight:700}.tok-decl{color:#ffd166;font-weight:700}.tok-call{color:#a8e6a1}.tok-method{color:#f4a261}.tok-string{color:#f7c59f}.tok-number{color:#f4d35e}.tok-comment{color:#8aa399}.tok-punct{color:#d7cdbb}.tok-ident{color:#f5efe0}
	input{font:inherit;padding:10px;border:1px solid #cbbfa8;border-radius:10px;background:#fff}
	button{font:inherit;padding:10px 14px;border:0;border-radius:10px;background:#146c5b;color:white}
	.danger{background:#9a3b2f}.inline-form{display:inline-block;margin:3px 4px 3px 0}.inline-form select{font:inherit;padding:8px;border:1px solid #cbbfa8;border-radius:10px;background:#fff}
	code,pre{background:#eee3d0;border-radius:8px;padding:2px 5px}pre{overflow:auto;padding:14px}
	table{width:100%;border-collapse:collapse}td,th{border-bottom:1px solid #e2d7c3;padding:8px;text-align:left}
	@media(max-width:760px){.brand{font-size:30px}main{padding:16px}input,button{width:100%;margin-top:8px}.package-card,.source-layout{grid-template-columns:1fr}.preview{max-width:none}}
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
	<article class="card package-card">
	  <div>
		  <h2><a href="/packages/{{.Publisher}}/{{.Name}}">{{if .Title}}{{.Title}}{{else}}{{.ID}}{{end}}</a></h2>
		  <p class="muted"><a href="/publishers/{{.Publisher}}">{{.Publisher}}</a>/{{.Name}}@{{.Version}}</p>
	  <p>{{.Summary}}</p>
	  <p>{{range .Tags}}<span class="pill">{{.}}</span>{{end}}</p>
	  </div>
	  {{if .ScreenshotURL}}<a href="/packages/{{.Publisher}}/{{.Name}}"><img class="preview" src="{{.ScreenshotURL}}" alt="{{if .Title}}{{.Title}}{{else}}{{.ID}}{{end}} screenshot"></a>{{end}}
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
	  {{if .Releases}}{{range .Releases}}{{range .Screenshots}}<p><img class="preview" src="{{.URL}}" alt="Package screenshot"></p>{{end}}{{end}}<table><tr><th>Version</th><th>Manifest</th><th>Program</th><th>Bundle</th><th>Capabilities</th><th>Source</th><th>Permissions</th><th>Status</th></tr>
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
		index=https://store.hubstack.cn/api/v0/index.json
		update=https://store.hubstack.cn/api/v0/packages/{{.Meta.Publisher}}/{{.Meta.Name}}/update?current_version=&lt;installed-version&gt;</pre></section>
	</main></body></html>`

const siteSourceHTML = `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{{.Meta.Publisher}}/{{.Meta.Name}} source - OBC Store</title><style>` + siteCSS + `</style></head>
<body><header><h1 class="brand">{{if .Meta.Title}}{{.Meta.Title}}{{else}}{{.Meta.Publisher}}/{{.Meta.Name}}{{end}} Source</h1><p>{{.Source.Path}} · {{.Release.Version}}</p></header>
<main>
<p><a href="/packages/{{.Meta.Publisher}}/{{.Meta.Name}}">Back to package</a> · <a href="/">Browse packages</a></p>
<section class="source-layout">
  <aside class="card">
    <h2>AST Outline</h2>
    {{if .Outline}}{{range .Outline}}<p><span class="pill">{{.Kind}}</span> <a href="#L{{.Line}}">{{.Name}}</a></p>{{end}}{{else}}<p class="muted">No top-level declarations found.</p>{{end}}
    <h2>Metadata</h2>
    <p class="muted">language={{.Source.Language}}<br>role={{.Source.Role}}</p>
  </aside>
  <pre class="source-code">{{range .Lines}}<span class="source-line" id="L{{.Number}}"><span class="ln">{{.Number}}</span>{{.HTML}}</span>
{{end}}</pre>
</section>
</main></body></html>`

const sitePublisherHTML = `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{{.Publisher.ID}} - OBC Store</title><style>` + siteCSS + `</style></head>
<body><header><h1 class="brand">{{if .Publisher.DisplayName}}{{.Publisher.DisplayName}}{{else}}{{.Publisher.ID}}{{end}}</h1><p>Public packages by {{.Publisher.ID}}.</p></header>
<main>
<p><a href="/">Browse packages</a> · <a href="/ops">operator guide</a> · <a href="/ops/status">operator status</a></p>
{{if .Packages}}{{range .Packages}}
	<article class="card package-card">
	  <div>
	  <h2><a href="/packages/{{.Publisher}}/{{.Name}}">{{if .Title}}{{.Title}}{{else}}{{.ID}}{{end}}</a></h2>
	  <p class="muted">{{.ID}}@{{.Version}}</p>
	  <p>{{.Summary}}</p>
	  <p>{{range .Tags}}<span class="pill">{{.}}</span>{{end}}</p>
	  </div>
	  {{if .ScreenshotURL}}<a href="/packages/{{.Publisher}}/{{.Name}}"><img class="preview" src="{{.ScreenshotURL}}" alt="{{if .Title}}{{.Title}}{{else}}{{.ID}}{{end}} screenshot"></a>{{end}}
	</article>
{{end}}{{else}}<div class="card">No public packages are currently published for this publisher.</div>{{end}}
</main></body></html>`

const siteOpsHTML = `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>OBC Store Operator Guide</title><style>` + siteCSS + `</style></head>
<body><header><h1 class="brand">Operator Guide</h1><p>Minimal publish and token lifecycle reference.</p></header>
<main>
	<section class="card"><h2>Deployment status</h2><p><a href="/ops/status">Authenticated operator status page</a> · <a href="/ops/releases">authenticated release lifecycle inventory</a> · <code>GET /api/v0/ops/status</code></p></section>
<section class="card"><h2>Public endpoints</h2><pre>GET /healthz
GET /api/v0/health
	GET /api/v0/index.json
		GET /api/v0/index.json.sig
		GET /api/v0/packages?query=plot&amp;capability=GFX
		GET /api/v0/packages/{publisher}/{name}/update?current_version=0.1.0</pre>
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
	<p><a href="/">Browse packages</a> · <a href="/ops">operator guide</a> · <a href="/ops/releases">release lifecycle</a> · <a href="/api/v0/ops/status">status JSON</a></p>
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
	<tr><th>Index signing key</th><td>{{if .IndexSigningKeyID}}{{.IndexSigningKeyID}}{{else}}not configured{{end}}</td></tr>
	<tr><th>Active key trusted</th><td>{{.IndexSigningKeyTrusted}}</td></tr>
	<tr><th>Trust bundle</th><td>{{.TrustBundleAvailable}} ({{.TrustBundleStoreKeys}} store key(s){{if .TrustBundleStoreKeyIDs}}: {{range $i, $id := .TrustBundleStoreKeyIDs}}{{if $i}}, {{end}}{{$id}}{{end}}{{end}})</td></tr>
	<tr><th>Admin auth</th><td>{{.AdminAuthConfigured}}</td></tr>
	<tr><th>Generated at</th><td>{{.GeneratedAt}}</td></tr>
	</table></section>
<section class="card"><h2>Smoke Commands</h2><pre>curl -fsS https://store.hubstack.cn/healthz
curl -fsS https://store.hubstack.cn/api/v0/index.json
	curl -fsS -u "$OBC_STORE_ADMIN_USERNAME:$OBC_STORE_ADMIN_PASSWORD" https://store.hubstack.cn/api/v0/ops/status</pre></section>
	</main></body></html>`

const siteOpsReleasesHTML = `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>OBC Store Release Lifecycle</title><style>` + siteCSS + `</style></head>
<body><header><h1 class="brand">Release Lifecycle</h1><p>Authenticated operator inventory for package visibility, release state, readiness, and next actions.</p></header>
<main>
<p><a href="/">Browse packages</a> · <a href="/ops">operator guide</a> · <a href="/ops/status">operator status</a> · <a href="/api/v0/ops/releases">JSON</a></p>
<section class="card">
{{if .Releases}}<table><tr><th>Package</th><th>Version</th><th>Status</th><th>Visibility</th><th>Readiness</th><th>Operator actions</th><th>Lifecycle endpoints</th></tr>
{{range .Releases}}<tr>
<td><a href="{{.PackageURL}}">{{.Publisher}}/{{.Name}}</a>{{if .Title}}<br><span class="muted">{{.Title}}</span>{{end}}</td>
<td>{{.Version}}{{if .LatestPublished}} <span class="pill">latest</span>{{end}}</td>
<td>{{.Status}}</td>
<td>{{.Visibility}}</td>
<td>{{range .Readiness}}<span class="pill">{{.}}</span>{{end}}{{range .MissingReadiness}}<span class="pill">missing {{.}}</span>{{end}}</td>
<td>
<form class="inline-form" method="post" action="{{.OpsPublishURL}}"><button type="submit">Publish</button></form>
<form class="inline-form" method="post" action="{{.OpsYankURL}}"><button class="danger" type="submit">Yank</button></form>
<form class="inline-form" method="post" action="{{.OpsVisibilityURL}}"><select name="visibility"><option value="public">public</option><option value="private">private</option></select><button type="submit">Set visibility</button></form>
</td>
<td><code>POST {{.PublishURL}}</code><br><code>POST {{.YankURL}}</code><br><code>POST {{.VisibilityURL}}</code></td>
</tr>{{end}}</table>{{else}}No package releases exist yet.{{end}}
</section>
</main></body></html>`
