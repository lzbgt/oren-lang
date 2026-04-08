package main

import (
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

const (
	obcMagic0 = 0xCD
	obcMagic1 = 0x0E

	obcConstNil    = 0
	obcConstInt    = 1
	obcConstBool   = 2
	obcConstFloat  = 3
	obcConstString = 4
	obcConstBytes  = 8

	sigPrefix = "OREN_SIG\n1\n"

	// Rolling cert chain payload embedded in `.obc` as an unused BYTES constant.
	// The AVM uses this chain to verify that a developer/org key is delegated by the root.
	certV1Prefix = "OREN_CERT\n1\n"
	certV2Prefix = "OREN_CERT\n2\n"
	certsPrefix  = "OREN_CERTS\n1\n"
)

func main() {
	prog := "orensign"
	if len(os.Args) > 0 {
		prog = os.Args[0]
	}
	os.Exit(runOrensign(prog, os.Args[1:], os.Stdout, os.Stderr))
}

func usage(prog string, errOut io.Writer) {
	fmt.Fprintln(errOut, "Usage:")
	fmt.Fprintf(errOut, "  %s keygen --out <dir>\n", prog)
	fmt.Fprintf(errOut, "  %s issue-cert --issuer-sk <issuer_sk.bin> --subject-pk <subject_pk.bin> --out <cert.bin> [--can-issue] [--allow-domains <csv>] [--allow-domains-mask <u64>]\n", prog)
	fmt.Fprintf(errOut, "  %s sign-obc --sk <path> --in <file.obc> [--cert <cert.bin> ...] [--out <signed.obc>]\n", prog)
	fmt.Fprintf(errOut, "  %s verify-obc --pk <path> --in <file.obc>\n", prog)
}

func keygenUsage(prog string, errOut io.Writer) {
	fmt.Fprintf(errOut, "Usage: %s keygen --out <dir>\n", prog)
}

func issueCertUsage(prog string, errOut io.Writer) {
	fmt.Fprintf(errOut, "Usage: %s issue-cert --issuer-sk <issuer_sk.bin> --subject-pk <subject_pk.bin> --out <cert.bin> [--can-issue] [--allow-domains <csv>] [--allow-domains-mask <u64>]\n", prog)
}

func signOBCUsage(prog string, errOut io.Writer) {
	fmt.Fprintf(errOut, "Usage: %s sign-obc --sk <path> --in <file.obc> [--cert <cert.bin> ...] [--out <signed.obc>]\n", prog)
}

func verifyOBCUsage(prog string, errOut io.Writer) {
	fmt.Fprintf(errOut, "Usage: %s verify-obc --pk <path> --in <file.obc>\n", prog)
}

func runOrensign(prog string, args []string, out, errOut io.Writer) int {
	if len(args) == 0 {
		usage(prog, errOut)
		return 2
	}
	switch args[0] {
	case "-h", "--help", "help":
		usage(prog, out)
		return 0
	case "keygen":
		return runKeygen(prog, args[1:], out, errOut)
	case "issue-cert":
		return runIssueCert(prog, args[1:], out, errOut)
	case "sign-obc":
		return runSignOBC(prog, args[1:], out, errOut)
	case "verify-obc":
		return runVerifyOBC(prog, args[1:], out, errOut)
	default:
		fmt.Fprintf(errOut, "ERROR: unknown command: %s\n", args[0])
		usage(prog, errOut)
		return 2
	}
}

func runKeygen(prog string, args []string, out, errOut io.Writer) int {
	fs := flag.NewFlagSet("keygen", flag.ContinueOnError)
	fs.SetOutput(errOut)
	fs.Usage = func() {
		keygenUsage(prog, errOut)
		fs.PrintDefaults()
	}
	outDir := fs.String("out", "", "output directory (created if missing)")
	if err := fs.Parse(args); err != nil {
		if err == flag.ErrHelp {
			return 0
		}
		return 2
	}
	if *outDir == "" {
		fmt.Fprintln(errOut, "ERROR: missing --out")
		keygenUsage(prog, errOut)
		return 2
	}
	if len(fs.Args()) != 0 {
		fmt.Fprintln(errOut, "ERROR: unexpected extra positional arguments")
		keygenUsage(prog, errOut)
		return 2
	}
	if err := os.MkdirAll(*outDir, 0o700); err != nil {
		fmt.Fprintf(errOut, "ERROR: failed to create output directory: %v\n", err)
		return 1
	}

	pk, sk, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		fmt.Fprintf(errOut, "ERROR: failed to generate ed25519 keypair: %v\n", err)
		return 1
	}

	skFile := filepath.Join(*outDir, "root_ed25519_sk.bin")
	pkFile := filepath.Join(*outDir, "root_ed25519_pk.bin")
	pkHexFile := filepath.Join(*outDir, "root_ed25519_pk.hex")
	keyIDFile := filepath.Join(*outDir, "root_ed25519_keyid.hex")
	if err := os.WriteFile(skFile, sk, 0o600); err != nil {
		fmt.Fprintf(errOut, "ERROR: failed to write %s: %v\n", skFile, err)
		return 1
	}
	if err := os.WriteFile(pkFile, pk, 0o644); err != nil {
		fmt.Fprintf(errOut, "ERROR: failed to write %s: %v\n", pkFile, err)
		return 1
	}
	if err := os.WriteFile(pkHexFile, []byte(hex.EncodeToString(pk)+"\n"), 0o644); err != nil {
		fmt.Fprintf(errOut, "ERROR: failed to write %s: %v\n", pkHexFile, err)
		return 1
	}

	keyID := sha256.Sum256(pk)
	if err := os.WriteFile(keyIDFile, []byte(hex.EncodeToString(keyID[:8])+"\n"), 0o644); err != nil {
		fmt.Fprintf(errOut, "ERROR: failed to write %s: %v\n", keyIDFile, err)
		return 1
	}
	fmt.Fprintln(out, "Wrote:")
	fmt.Fprintln(out, " ", skFile)
	fmt.Fprintln(out, " ", pkFile)
	return 0
}

func runSignOBC(prog string, args []string, out, errOut io.Writer) int {
	fs := flag.NewFlagSet("sign-obc", flag.ContinueOnError)
	fs.SetOutput(errOut)
	fs.Usage = func() {
		signOBCUsage(prog, errOut)
		fs.PrintDefaults()
	}
	skPath := fs.String("sk", "", "ed25519 private key (root_ed25519_sk.bin)")
	inPath := fs.String("in", "", "input .obc")
	outPath := fs.String("out", "", "output signed .obc (default: overwrite input)")
	var certPaths stringSliceFlag
	fs.Var(&certPaths, "cert", "optional certificate to embed (repeatable, leaf-first)")
	if err := fs.Parse(args); err != nil {
		if err == flag.ErrHelp {
			return 0
		}
		return 2
	}
	if *skPath == "" || *inPath == "" {
		fmt.Fprintln(errOut, "ERROR: missing --sk or --in")
		signOBCUsage(prog, errOut)
		return 2
	}
	if len(fs.Args()) != 0 {
		fmt.Fprintln(errOut, "ERROR: unexpected extra positional arguments")
		signOBCUsage(prog, errOut)
		return 2
	}
	if *outPath == "" {
		*outPath = *inPath
	}
	sk, err := os.ReadFile(*skPath)
	if err != nil {
		fmt.Fprintf(errOut, "ERROR: failed to read private key: %v\n", err)
		return 1
	}
	if l := len(sk); l != ed25519.PrivateKeySize {
		fmt.Fprintf(errOut, "ERROR: bad ed25519 private key length: got %d want %d\n", l, ed25519.PrivateKeySize)
		return 1
	}
	pk := ed25519.PrivateKey(sk).Public().(ed25519.PublicKey)

	raw, err := os.ReadFile(*inPath)
	if err != nil {
		fmt.Fprintf(errOut, "ERROR: failed to read input obc: %v\n", err)
		return 1
	}

	canon, err := obcCanonicalNoSig(raw)
	if err != nil {
		fmt.Fprintf(errOut, "ERROR: invalid obc for signing: %v\n", err)
		return 1
	}
	h := sha256.Sum256(canon)

	sig := ed25519.Sign(ed25519.PrivateKey(sk), h[:])
	payload := buildSigPayload(pk, sig)

	var certsPayload []byte
	if len(certPaths) > 0 {
		certs := make([][]byte, 0, len(certPaths))
		for _, p := range certPaths {
			certBytes, err := os.ReadFile(p)
			if err != nil {
				fmt.Fprintf(errOut, "ERROR: failed to read cert %s: %v\n", p, err)
				return 1
			}
			certs = append(certs, certBytes)
		}
		certsPayload = buildCertsPayload(certs)
	}

	signed, err := obcWithSigAndCerts(raw, payload, certsPayload)
	if err != nil {
		fmt.Fprintf(errOut, "ERROR: failed to attach signature: %v\n", err)
		return 1
	}
	if err := os.WriteFile(*outPath, signed, 0o644); err != nil {
		fmt.Fprintf(errOut, "ERROR: failed to write signed obc: %v\n", err)
		return 1
	}
	fmt.Fprintln(out, "Signed:", *outPath)
	return 0
}

func runVerifyOBC(prog string, args []string, out, errOut io.Writer) int {
	fs := flag.NewFlagSet("verify-obc", flag.ContinueOnError)
	fs.SetOutput(errOut)
	fs.Usage = func() {
		verifyOBCUsage(prog, errOut)
		fs.PrintDefaults()
	}
	pkPath := fs.String("pk", "", "ed25519 public key (root_ed25519_pk.bin)")
	inPath := fs.String("in", "", "input .obc")
	if err := fs.Parse(args); err != nil {
		if err == flag.ErrHelp {
			return 0
		}
		return 2
	}
	if *pkPath == "" || *inPath == "" {
		fmt.Fprintln(errOut, "ERROR: missing --pk or --in")
		verifyOBCUsage(prog, errOut)
		return 2
	}
	if len(fs.Args()) != 0 {
		fmt.Fprintln(errOut, "ERROR: unexpected extra positional arguments")
		verifyOBCUsage(prog, errOut)
		return 2
	}
	pk, err := os.ReadFile(*pkPath)
	if err != nil {
		fmt.Fprintf(errOut, "ERROR: failed to read public key: %v\n", err)
		return 1
	}
	if l := len(pk); l != ed25519.PublicKeySize {
		fmt.Fprintf(errOut, "ERROR: bad ed25519 public key length: got %d want %d\n", l, ed25519.PublicKeySize)
		return 1
	}

	raw, err := os.ReadFile(*inPath)
	if err != nil {
		fmt.Fprintf(errOut, "ERROR: failed to read input obc: %v\n", err)
		return 1
	}
	payload, err := obcExtractSigPayload(raw)
	if err != nil {
		fmt.Fprintf(errOut, "ERROR: invalid obc: %v\n", err)
		return 1
	}
	if payload == nil {
		fmt.Fprintln(errOut, "ERROR: missing OREN_SIG payload")
		return 1
	}
	keyID, sig, err := parseSigPayload(payload)
	if err != nil {
		fmt.Fprintf(errOut, "ERROR: invalid OREN_SIG payload: %v\n", err)
		return 1
	}
	_ = keyID // reserved for multi-key trust sets

	canon, err := obcCanonicalNoSig(raw)
	if err != nil {
		fmt.Fprintf(errOut, "ERROR: invalid obc for verification: %v\n", err)
		return 1
	}
	h := sha256.Sum256(canon)

	if !ed25519.Verify(ed25519.PublicKey(pk), h[:], sig) {
		fmt.Fprintln(errOut, "ERROR: signature verification failed")
		return 1
	}
	fmt.Fprintln(out, "OK")
	return 0
}

func runIssueCert(prog string, args []string, out, errOut io.Writer) int {
	fs := flag.NewFlagSet("issue-cert", flag.ContinueOnError)
	fs.SetOutput(errOut)
	fs.Usage = func() {
		issueCertUsage(prog, errOut)
		fs.PrintDefaults()
	}
	issuerSKPath := fs.String("issuer-sk", "", "issuer ed25519 private key (root/org)")
	subjectPKPath := fs.String("subject-pk", "", "subject ed25519 public key (org/dev)")
	outPath := fs.String("out", "", "output cert file (raw bytes)")
	canIssue := fs.Bool("can-issue", false, "allow subject to issue derived certs")
	allowDomains := fs.String("allow-domains", "", "optional CSV allowlist of AVM native domains (CORE,FS,TIME,RNG,NET,PROC,EXIT,ENV,AVM,ALL); empty means inherit")
	allowDomainsMask := fs.String("allow-domains-mask", "", "optional u64 mask allowlist (hex 0x... or decimal); 0 means inherit")
	if err := fs.Parse(args); err != nil {
		if err == flag.ErrHelp {
			return 0
		}
		return 2
	}
	if *issuerSKPath == "" || *subjectPKPath == "" || *outPath == "" {
		fmt.Fprintln(errOut, "ERROR: missing --issuer-sk, --subject-pk, or --out")
		issueCertUsage(prog, errOut)
		return 2
	}
	if len(fs.Args()) != 0 {
		fmt.Fprintln(errOut, "ERROR: unexpected extra positional arguments")
		issueCertUsage(prog, errOut)
		return 2
	}
	issuerSK, err := os.ReadFile(*issuerSKPath)
	if err != nil {
		fmt.Fprintf(errOut, "ERROR: failed to read issuer private key: %v\n", err)
		return 1
	}
	if len(issuerSK) != ed25519.PrivateKeySize {
		fmt.Fprintf(errOut, "ERROR: bad issuer sk length: got %d want %d\n", len(issuerSK), ed25519.PrivateKeySize)
		return 1
	}
	issuerPK := ed25519.PrivateKey(issuerSK).Public().(ed25519.PublicKey)

	subjectPK, err := os.ReadFile(*subjectPKPath)
	if err != nil {
		fmt.Fprintf(errOut, "ERROR: failed to read subject public key: %v\n", err)
		return 1
	}
	if len(subjectPK) != ed25519.PublicKeySize {
		fmt.Fprintf(errOut, "ERROR: bad subject pk length: got %d want %d\n", len(subjectPK), ed25519.PublicKeySize)
		return 1
	}

	flags := byte(0)
	if *canIssue {
		flags |= 0x01
	}

	if *allowDomains != "" && *allowDomainsMask != "" {
		fmt.Fprintln(errOut, "ERROR: cannot use both --allow-domains and --allow-domains-mask")
		issueCertUsage(prog, errOut)
		return 2
	}
	var allowMask uint64 = 0
	if *allowDomains != "" {
		m, err := parseAllowDomainsCSV(*allowDomains)
		if err != nil {
			fmt.Fprintf(errOut, "ERROR: invalid --allow-domains value: %v\n", err)
			return 2
		}
		allowMask = m
	} else if *allowDomainsMask != "" {
		m, err := parseU64(*allowDomainsMask)
		if err != nil {
			fmt.Fprintf(errOut, "ERROR: invalid --allow-domains-mask value: %v\n", err)
			return 2
		}
		allowMask = m
	}

	// Rolling: issue OREN_CERT v2 by default (adds allow_domains_mask field).
	bodyNoSig := buildCertV2BodyNoSig(flags, issuerPK, subjectPK, allowMask)
	bodyHash := sha256.Sum256(bodyNoSig)
	sig := ed25519.Sign(ed25519.PrivateKey(issuerSK), bodyHash[:])
	cert := append(bodyNoSig, sig...)

	if err := os.WriteFile(*outPath, cert, 0o644); err != nil {
		fmt.Fprintf(errOut, "ERROR: failed to write cert: %v\n", err)
		return 1
	}
	fmt.Fprintln(out, "Wrote cert:", *outPath)
	return 0
}

func buildCertV2BodyNoSig(flags byte, issuerPK ed25519.PublicKey, subjectPK []byte, allowDomainsMask uint64) []byte {
	var out bytes.Buffer
	out.WriteString(certV2Prefix)
	out.WriteByte(1) // algo=1 ed25519
	out.WriteByte(flags)
	// not_before, not_after (u64 LE). 0 means "unset" in rolling v0.
	writeU64LE(&out, 0)
	writeU64LE(&out, 0)
	out.Write(subjectPK)
	issuerKeyID := sha256.Sum256(issuerPK)
	out.Write(issuerKeyID[:8])
	// v2: allow_domains_mask (u64 LE). 0 means "inherit issuer's effective mask".
	writeU64LE(&out, allowDomainsMask)
	return out.Bytes()
}

func buildCertsPayload(certs [][]byte) []byte {
	var out bytes.Buffer
	out.WriteString(certsPrefix)
	writeU16LE(&out, uint16(len(certs)))
	for _, c := range certs {
		writeU16LE(&out, uint16(len(c)))
		out.Write(c)
	}
	return out.Bytes()
}

func buildSigPayload(pub ed25519.PublicKey, sig []byte) []byte {
	keyID := sha256.Sum256(pub)
	var out bytes.Buffer
	out.WriteString(sigPrefix)
	// v1:
	// u8 algo=1 (ed25519)
	// u8 hash=1 (sha256 over canonical_no_sig obc bytes)
	// key_id[8] (sha256(pubkey)[:8])
	// sig[64]
	out.WriteByte(1)
	out.WriteByte(1)
	out.Write(keyID[:8])
	out.Write(sig)
	return out.Bytes()
}

func parseSigPayload(payload []byte) (keyID [8]byte, sig []byte, err error) {
	if !bytes.HasPrefix(payload, []byte(sigPrefix)) {
		return keyID, nil, errors.New("bad sig prefix")
	}
	p := payload[len(sigPrefix):]
	if len(p) < 1+1+8+64 {
		return keyID, nil, errors.New("sig payload too short")
	}
	algo := p[0]
	hash := p[1]
	if algo != 1 || hash != 1 {
		return keyID, nil, fmt.Errorf("unsupported sig algo/hash: %d/%d", algo, hash)
	}
	copy(keyID[:], p[2:10])
	sig = make([]byte, 64)
	copy(sig, p[10:10+64])
	return keyID, sig, nil
}

func obcExtractSigPayload(obc []byte) ([]byte, error) {
	_, consts, _, err := obcSplit(obc)
	if err != nil {
		return nil, err
	}
	for _, c := range consts {
		if c.typ == obcConstBytes && bytes.HasPrefix(c.bytesPayload, []byte(sigPrefix)) {
			return c.bytesPayload, nil
		}
	}
	return nil, nil
}

func obcCanonicalNoSig(obc []byte) ([]byte, error) {
	code, consts, _, err := obcSplit(obc)
	if err != nil {
		return nil, err
	}
	kept := make([]obcConst, 0, len(consts))
	for _, c := range consts {
		if c.typ == obcConstBytes && bytes.HasPrefix(c.bytesPayload, []byte(sigPrefix)) {
			continue
		}
		if c.typ == obcConstBytes && bytes.HasPrefix(c.bytesPayload, []byte(certsPrefix)) {
			continue
		}
		kept = append(kept, c)
	}

	var out bytes.Buffer
	out.WriteByte(obcMagic0)
	out.WriteByte(obcMagic1)
	writeU16LE(&out, uint16(len(kept)))
	for _, c := range kept {
		if err := c.encode(&out); err != nil {
			return nil, err
		}
	}
	out.Write(code)
	return out.Bytes(), nil
}

func obcWithSig(obc []byte, sigPayload []byte) ([]byte, error) {
	return obcWithSigAndCerts(obc, sigPayload, nil)
}

func obcWithSigAndCerts(obc []byte, sigPayload []byte, certsPayload []byte) ([]byte, error) {
	code, consts, _, err := obcSplit(obc)
	if err != nil {
		return nil, err
	}
	kept := make([]obcConst, 0, len(consts)+2)
	for _, c := range consts {
		if c.typ == obcConstBytes && bytes.HasPrefix(c.bytesPayload, []byte(sigPrefix)) {
			continue
		}
		if c.typ == obcConstBytes && bytes.HasPrefix(c.bytesPayload, []byte(certsPrefix)) {
			continue
		}
		kept = append(kept, c)
	}
	if certsPayload != nil && len(certsPayload) > 0 {
		kept = append(kept, obcConst{typ: obcConstBytes, bytesPayload: certsPayload})
	}
	kept = append(kept, obcConst{typ: obcConstBytes, bytesPayload: sigPayload})

	var out bytes.Buffer
	out.WriteByte(obcMagic0)
	out.WriteByte(obcMagic1)
	writeU16LE(&out, uint16(len(kept)))
	for _, c := range kept {
		if err := c.encode(&out); err != nil {
			return nil, err
		}
	}
	out.Write(code)
	return out.Bytes(), nil
}

type stringSliceFlag []string

func (s *stringSliceFlag) String() string {
	if s == nil || len(*s) == 0 {
		return ""
	}
	return strings.Join(*s, ",")
}

func (s *stringSliceFlag) Set(v string) error {
	*s = append(*s, v)
	return nil
}

type obcConst struct {
	typ          byte
	raw          []byte // full encoded constant bytes (type+payload)
	bytesPayload []byte
}

func (c obcConst) encode(w io.Writer) error {
	if c.raw != nil {
		_, err := w.Write(c.raw)
		return err
	}
	// Only BYTES constants need re-encoding in our current usage.
	if c.typ != obcConstBytes {
		return errors.New("unsupported const encode without raw")
	}
	if _, err := w.Write([]byte{obcConstBytes}); err != nil {
		return err
	}
	writeU32LE(w, uint32(len(c.bytesPayload)))
	_, err := w.Write(c.bytesPayload)
	return err
}

func obcSplit(obc []byte) (code []byte, consts []obcConst, codePos int, err error) {
	if len(obc) < 4 || obc[0] != obcMagic0 || obc[1] != obcMagic1 {
		return nil, nil, 0, errors.New("bad obc magic")
	}
	pos := 2
	nConsts := int(readU16LE(obc, pos))
	pos += 2
	consts = make([]obcConst, 0, nConsts)
	for i := 0; i < nConsts; i++ {
		if pos >= len(obc) {
			return nil, nil, 0, errors.New("truncated const pool")
		}
		start := pos
		typ := obc[pos]
		pos++
		switch typ {
		case obcConstNil:
			// no payload
		case obcConstInt:
			pos += 8
		case obcConstBool:
			pos += 1
		case obcConstFloat:
			pos += 8
		case obcConstString:
			if pos+2 > len(obc) {
				return nil, nil, 0, errors.New("truncated string len")
			}
			slen := int(readU16LE(obc, pos))
			pos += 2 + slen
		case obcConstBytes:
			if pos+4 > len(obc) {
				return nil, nil, 0, errors.New("truncated bytes len")
			}
			blen := int(readU32LE(obc, pos))
			pos += 4
			if pos+blen > len(obc) {
				return nil, nil, 0, errors.New("truncated bytes payload")
			}
			payload := make([]byte, blen)
			copy(payload, obc[pos:pos+blen])
			pos += blen
			consts = append(consts, obcConst{
				typ:          typ,
				raw:          append([]byte(nil), obc[start:pos]...),
				bytesPayload: payload,
			})
			continue
		default:
			return nil, nil, 0, fmt.Errorf("unknown const tag: %d", typ)
		}
		if pos > len(obc) {
			return nil, nil, 0, errors.New("truncated const payload")
		}
		consts = append(consts, obcConst{
			typ: typ,
			raw: append([]byte(nil), obc[start:pos]...),
		})
	}
	codePos = pos
	code = obc[pos:]
	return code, consts, codePos, nil
}

func readU16LE(b []byte, pos int) uint16 {
	return uint16(b[pos]) | (uint16(b[pos+1]) << 8)
}

func readU32LE(b []byte, pos int) uint32 {
	return uint32(b[pos]) | (uint32(b[pos+1]) << 8) | (uint32(b[pos+2]) << 16) | (uint32(b[pos+3]) << 24)
}

func writeU16LE(w io.Writer, v uint16) {
	_, _ = w.Write([]byte{byte(v), byte(v >> 8)})
}

func writeU32LE(w io.Writer, v uint32) {
	_, _ = w.Write([]byte{byte(v), byte(v >> 8), byte(v >> 16), byte(v >> 24)})
}

func writeU64LE(w io.Writer, v uint64) {
	_, _ = w.Write([]byte{
		byte(v),
		byte(v >> 8),
		byte(v >> 16),
		byte(v >> 24),
		byte(v >> 32),
		byte(v >> 40),
		byte(v >> 48),
		byte(v >> 56),
	})
}

func parseU64(s string) (uint64, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, errors.New("empty u64")
	}
	// base=0 supports: 123, 0x7b, 077, etc.
	return strconv.ParseUint(s, 0, 64)
}

func parseAllowDomainsCSV(s string) (uint64, error) {
	// Tokens are case-insensitive, comma-separated.
	// Kept in sync with AVM parse_oren_domains_mask() (CORE,FS,TIME,RNG,NET,PROC,EXIT,ENV,AVM,ALL).
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, nil
	}
	var mask uint64 = 0
	sawAny := false
	for _, tok := range strings.Split(s, ",") {
		t := strings.TrimSpace(tok)
		if t == "" {
			continue
		}
		sawAny = true
		t = strings.ToUpper(t)
		switch t {
		case "ALL":
			mask |= ^uint64(0)
		case "CORE":
			mask |= 1 << 0
		case "FS":
			mask |= 1 << 1
		case "TIME":
			mask |= 1 << 2
		case "RNG":
			mask |= 1 << 3
		case "NET":
			mask |= 1 << 4
		case "PROC":
			mask |= 1 << 5
		case "EXIT":
			mask |= 1 << 6
		case "ENV":
			mask |= 1 << 7
		case "AVM":
			mask |= 1 << 8
		default:
			return 0, fmt.Errorf("unknown allow-domains token: %q", t)
		}
	}
	if !sawAny {
		return 0, errors.New("no allow-domains tokens")
	}
	return mask, nil
}
