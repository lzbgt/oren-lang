package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"
)

// oredoc is a small repo tool for turning Oren compiler metadata into higher-level
// artifacts (OpenAPI, etc).
//
// It is intentionally separate from the self-hosted compiler sources (`lib/compiler/*.oren`)
// to keep orchestration/tooling SOLID.

type metaFile struct {
	Structs []metaStruct `json:"structs"`
}

type metaStruct struct {
	Name  string       `json:"name"`
	Serde *serdeSchema `json:"serde,omitempty"`
}

type serdeSchema struct {
	Version int          `json:"version"`
	Format  string       `json:"format"`
	Tag     string       `json:"tag,omitempty"`
	Fields  []serdeField `json:"fields"`
}

type serdeField struct {
	Name    string      `json:"name"`
	AnnType string      `json:"ann_type"`
	Wire    string      `json:"wire,omitempty"`
	Skip    bool        `json:"skip"`
	Default interface{} `json:"default"`
}

func usage(prog string, errOut io.Writer) {
	fmt.Fprintf(errOut, "Usage:\n")
	fmt.Fprintf(errOut, "  %s openapi <meta.json> [-o out.json] [-title T] [-version V] [-format json]\n", prog)
}

func openAPIUsage(prog string, errOut io.Writer) {
	fmt.Fprintf(errOut, "Usage: %s openapi <meta.json> [-o out.json] [-title T] [-version V] [-format json]\n", prog)
}

func runOredoc(prog string, args []string, out, errOut io.Writer) int {
	if len(args) == 0 {
		usage(prog, errOut)
		return 2
	}
	switch args[0] {
	case "-h", "--help", "help":
		usage(prog, out)
		return 0
	case "openapi":
		return runOpenAPI(prog, args[1:], out, errOut)
	default:
		fmt.Fprintf(errOut, "ERROR: unknown command: %s\n", args[0])
		usage(prog, errOut)
		return 2
	}
}

func main() {
	prog := "oredoc"
	if len(os.Args) > 0 {
		prog = os.Args[0]
	}
	os.Exit(runOredoc(prog, os.Args[1:], os.Stdout, os.Stderr))
}

func runOpenAPI(prog string, args []string, out, errOut io.Writer) int {
	fs := flag.NewFlagSet("openapi", flag.ContinueOnError)
	fs.SetOutput(errOut)
	fs.Usage = func() {
		openAPIUsage(prog, errOut)
		fs.PrintDefaults()
	}

	var (
		outPath = fs.String("o", "", "write output to file (default: stdout)")
		title   = fs.String("title", "Oren API", "OpenAPI info.title")
		version = fs.String("version", "0.0.0", "OpenAPI info.version")
		format  = fs.String("format", "json", "serde format to export (default: json)")
	)

	// `oredoc openapi` uses one required positional arg: `<meta.json>`.
	// Allow it to appear before flags (common CLI style).
	metaPath := ""
	if len(args) > 0 && !strings.HasPrefix(args[0], "-") {
		metaPath = args[0]
		args = args[1:]
	}

	// Go's standard flag package only accepts single-dash flags (`-title`), but users
	// naturally type GNU-style `--title`. Accept both to make tooling smoother.
	args2 := make([]string, 0, len(args))
	for _, a := range args {
		if strings.HasPrefix(a, "--") && len(a) > 2 {
			args2 = append(args2, "-"+a[2:])
		} else {
			args2 = append(args2, a)
		}
	}

	if err := fs.Parse(args2); err != nil {
		if err == flag.ErrHelp {
			return 0
		}
		return 2
	}
	rest := fs.Args()
	if metaPath == "" {
		if len(rest) != 1 {
			fmt.Fprintln(errOut, "ERROR: missing <meta.json>")
			usage(prog, errOut)
			return 2
		}
		metaPath = rest[0]
	} else if len(rest) != 0 {
		fmt.Fprintln(errOut, "ERROR: unexpected extra positional arguments")
		usage(prog, errOut)
		return 2
	}

	raw, err := os.ReadFile(metaPath)
	if err != nil {
		fmt.Fprintf(errOut, "ERROR: failed to read meta: %v\n", err)
		return 1
	}

	var mf metaFile
	if err := json.Unmarshal(raw, &mf); err != nil {
		fmt.Fprintf(errOut, "ERROR: invalid meta json: %v\n", err)
		return 1
	}

	doc := exportOpenAPI(&mf, *title, *version, *format)
	docBytes, err := json.MarshalIndent(doc, "", "  ")
	if err != nil {
		fmt.Fprintf(errOut, "ERROR: failed to encode openapi: %v\n", err)
		return 1
	}
	docBytes = append(docBytes, '\n')

	if *outPath == "" {
		_, _ = out.Write(docBytes)
		return 0
	}
	if err := os.WriteFile(*outPath, docBytes, 0o644); err != nil {
		fmt.Fprintf(errOut, "ERROR: failed to write output: %v\n", err)
		return 1
	}
	return 0
}

func exportOpenAPI(mf *metaFile, title, version, format string) map[string]interface{} {
	schemas := map[string]interface{}{}

	// Sort for stable output in rolling mode (even though json marshaler sorts map keys,
	// struct iteration order still matters for deterministic "required" lists).
	structs := append([]metaStruct(nil), mf.Structs...)
	sort.Slice(structs, func(i, j int) bool { return structs[i].Name < structs[j].Name })

	for _, st := range structs {
		if st.Serde == nil {
			continue
		}
		if st.Serde.Format != "" && format != "" && st.Serde.Format != format {
			continue
		}
		schemas[st.Name] = serdeStructToSchema(st.Name, st.Serde)
	}

	// Minimal valid OpenAPI 3.1 document:
	// - openapi
	// - info
	// - paths
	// components is optional but useful.
	return map[string]interface{}{
		"openapi": "3.1.0",
		"info": map[string]interface{}{
			"title":   title,
			"version": version,
		},
		"paths": map[string]interface{}{},
		"components": map[string]interface{}{
			"schemas": schemas,
		},
	}
}

func serdeStructToSchema(name string, s *serdeSchema) map[string]interface{} {
	props := map[string]interface{}{}
	var required []string

	// Tag support (rolling): serde tag becomes a discriminator-like constant field `t`
	// for the JSON object shape produced by current serde helpers.
	if s.Tag != "" {
		props["t"] = map[string]interface{}{
			"type":  "string",
			"const": s.Tag,
		}
		required = append(required, "t")
	}

	fields := append([]serdeField(nil), s.Fields...)
	sort.Slice(fields, func(i, j int) bool { return fields[i].Name < fields[j].Name })

	for _, f := range fields {
		if f.Skip {
			continue
		}
		wire := f.Wire
		if wire == "" {
			wire = f.Name
		}
		props[wire] = schemaForAnnType(f.AnnType)

		// Required rule (v0):
		// - if a default exists, decoding can succeed when missing -> not required
		// - otherwise required
		if f.Default == nil {
			required = append(required, wire)
		}
	}

	sort.Strings(required)

	schema := map[string]interface{}{
		"type":                 "object",
		"additionalProperties": false,
		"properties":           props,
	}
	if len(required) > 0 {
		schema["required"] = required
	}
	return schema
}

func schemaForAnnType(ann string) map[string]interface{} {
	ann = strings.TrimSpace(ann)
	if ann == "" {
		return map[string]interface{}{}
	}

	// Array type sugar from compiler metadata: "[]T".
	if strings.HasPrefix(ann, "[]") {
		inner := strings.TrimSpace(strings.TrimPrefix(ann, "[]"))
		return map[string]interface{}{
			"type":  "array",
			"items": schemaForAnnType(inner),
		}
	}

	// Scalars (rolling):
	// - Oren ints are i64 in runtime today; annotated widths are about ABI/FFI/layout.
	// - For OpenAPI, we map widths to `format` and preserve unsignedness via minimum=0.
	switch ann {
	case "string":
		return map[string]interface{}{"type": "string"}
	case "bool":
		return map[string]interface{}{"type": "boolean"}
	case "bytes":
		return map[string]interface{}{"type": "string", "format": "byte"}
	case "f32":
		return map[string]interface{}{"type": "number", "format": "float"}
	case "f64":
		return map[string]interface{}{"type": "number", "format": "double"}
	}

	// Integers.
	// Note: OpenAPI only has signed formats. We still use int32/int64 formats and
	// add minimum=0 for unsigned spellings.
	if isUnsignedIntAnn(ann) {
		return map[string]interface{}{
			"type":    "integer",
			"format":  intFormatForWidth(ann),
			"minimum": 0,
		}
	}
	if isSignedIntAnn(ann) {
		return map[string]interface{}{
			"type":   "integer",
			"format": intFormatForWidth(ann),
		}
	}

	// 128-bit: JSON wire formats are typically string (avoid loss in JS/clients).
	if ann == "u128" || ann == "i128" {
		return map[string]interface{}{
			"type":        "string",
			"description": "128-bit integer (string-encoded for JSON/OpenAPI portability)",
		}
	}

	// Struct reference: expose as $ref to components schema.
	// (If the schema isn't present, this is still a reasonable forward reference.)
	return map[string]interface{}{
		"$ref": "#/components/schemas/" + ann,
	}
}

func isUnsignedIntAnn(ann string) bool {
	switch ann {
	case "u8", "u16", "u32", "u64", "u16be", "u16le", "u32be", "u32le", "u64be", "u64le":
		return true
	default:
		return false
	}
}

func isSignedIntAnn(ann string) bool {
	switch ann {
	case "i8", "i16", "i32", "i64", "i16be", "i16le", "i32be", "i32le", "i64be", "i64le":
		return true
	default:
		return false
	}
}

func intFormatForWidth(ann string) string {
	// Endian spellings share the same width.
	switch ann {
	case "u8", "i8", "u16", "i16", "u16be", "u16le", "i16be", "i16le", "u32", "i32", "u32be", "u32le", "i32be", "i32le":
		return "int32"
	default:
		return "int64"
	}
}
