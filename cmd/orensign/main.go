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
	certsPrefix = "OREN_CERTS\n1\n"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	switch os.Args[1] {
	case "keygen":
		cmdKeygen(os.Args[2:])
	case "issue-cert":
		cmdIssueCert(os.Args[2:])
	case "sign-obc":
		cmdSignOBC(os.Args[2:])
	case "verify-obc":
		cmdVerifyOBC(os.Args[2:])
	default:
		usage()
		os.Exit(2)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, "Usage:")
	fmt.Fprintln(os.Stderr, "  orensign keygen --out <dir>")
	fmt.Fprintln(os.Stderr, "  orensign issue-cert --issuer-sk <issuer_sk.bin> --subject-pk <subject_pk.bin> --out <cert.bin> [--can-issue] [--allow-domains <csv>] [--allow-domains-mask <u64>]")
	fmt.Fprintln(os.Stderr, "  orensign sign-obc --sk <path> --in <file.obc> [--cert <cert.bin> ...] [--out <signed.obc>]")
	fmt.Fprintln(os.Stderr, "  orensign verify-obc --pk <path> --in <file.obc>")
}

func must(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERROR:", err)
		os.Exit(1)
	}
}

func cmdKeygen(args []string) {
	fs := flag.NewFlagSet("keygen", flag.ExitOnError)
	outDir := fs.String("out", "", "output directory (created if missing)")
	must(fs.Parse(args))
	if *outDir == "" {
		must(errors.New("missing --out"))
	}
	must(os.MkdirAll(*outDir, 0o700))

	pk, sk, err := ed25519.GenerateKey(rand.Reader)
	must(err)

	must(os.WriteFile(filepath.Join(*outDir, "root_ed25519_sk.bin"), sk, 0o600))
	must(os.WriteFile(filepath.Join(*outDir, "root_ed25519_pk.bin"), pk, 0o644))
	must(os.WriteFile(filepath.Join(*outDir, "root_ed25519_pk.hex"), []byte(hex.EncodeToString(pk)+"\n"), 0o644))

	keyID := sha256.Sum256(pk)
	must(os.WriteFile(filepath.Join(*outDir, "root_ed25519_keyid.hex"), []byte(hex.EncodeToString(keyID[:8])+"\n"), 0o644))
	fmt.Println("Wrote:")
	fmt.Println(" ", filepath.Join(*outDir, "root_ed25519_sk.bin"))
	fmt.Println(" ", filepath.Join(*outDir, "root_ed25519_pk.bin"))
}

func cmdSignOBC(args []string) {
	fs := flag.NewFlagSet("sign-obc", flag.ExitOnError)
	skPath := fs.String("sk", "", "ed25519 private key (root_ed25519_sk.bin)")
	inPath := fs.String("in", "", "input .obc")
	outPath := fs.String("out", "", "output signed .obc (default: overwrite input)")
	var certPaths stringSliceFlag
	fs.Var(&certPaths, "cert", "optional certificate to embed (repeatable, leaf-first)")
	must(fs.Parse(args))
	if *skPath == "" || *inPath == "" {
		must(errors.New("missing --sk or --in"))
	}
	if *outPath == "" {
		*outPath = *inPath
	}
	sk, err := os.ReadFile(*skPath)
	must(err)
	if l := len(sk); l != ed25519.PrivateKeySize {
		must(fmt.Errorf("bad ed25519 private key length: got %d want %d", l, ed25519.PrivateKeySize))
	}
	pk := ed25519.PrivateKey(sk).Public().(ed25519.PublicKey)

	raw, err := os.ReadFile(*inPath)
	must(err)

	canon, err := obcCanonicalNoSig(raw)
	must(err)
	h := sha256.Sum256(canon)

	sig := ed25519.Sign(ed25519.PrivateKey(sk), h[:])
	payload := buildSigPayload(pk, sig)

	var certsPayload []byte
	if len(certPaths) > 0 {
		certs := make([][]byte, 0, len(certPaths))
		for _, p := range certPaths {
			certBytes, err := os.ReadFile(p)
			must(err)
			certs = append(certs, certBytes)
		}
		certsPayload = buildCertsPayload(certs)
	}

	signed, err := obcWithSigAndCerts(raw, payload, certsPayload)
	must(err)
	must(os.WriteFile(*outPath, signed, 0o644))
	fmt.Println("Signed:", *outPath)
}

func cmdVerifyOBC(args []string) {
	fs := flag.NewFlagSet("verify-obc", flag.ExitOnError)
	pkPath := fs.String("pk", "", "ed25519 public key (root_ed25519_pk.bin)")
	inPath := fs.String("in", "", "input .obc")
	must(fs.Parse(args))
	if *pkPath == "" || *inPath == "" {
		must(errors.New("missing --pk or --in"))
	}
	pk, err := os.ReadFile(*pkPath)
	must(err)
	if l := len(pk); l != ed25519.PublicKeySize {
		must(fmt.Errorf("bad ed25519 public key length: got %d want %d", l, ed25519.PublicKeySize))
	}

	raw, err := os.ReadFile(*inPath)
	must(err)
	payload, err := obcExtractSigPayload(raw)
	must(err)
	if payload == nil {
		must(errors.New("missing OREN_SIG payload"))
	}
	keyID, sig, err := parseSigPayload(payload)
	must(err)
	_ = keyID // reserved for multi-key trust sets

	canon, err := obcCanonicalNoSig(raw)
	must(err)
	h := sha256.Sum256(canon)

	if !ed25519.Verify(ed25519.PublicKey(pk), h[:], sig) {
		must(errors.New("signature verification failed"))
	}
	fmt.Println("OK")
}

func cmdIssueCert(args []string) {
	fs := flag.NewFlagSet("issue-cert", flag.ExitOnError)
	issuerSKPath := fs.String("issuer-sk", "", "issuer ed25519 private key (root/org)")
	subjectPKPath := fs.String("subject-pk", "", "subject ed25519 public key (org/dev)")
	outPath := fs.String("out", "", "output cert file (raw bytes)")
	canIssue := fs.Bool("can-issue", false, "allow subject to issue derived certs")
	allowDomains := fs.String("allow-domains", "", "optional CSV allowlist of AVM native domains (CORE,FS,TIME,RNG,NET,PROC,EXIT,ENV,AVM,ALL); empty means inherit")
	allowDomainsMask := fs.String("allow-domains-mask", "", "optional u64 mask allowlist (hex 0x... or decimal); 0 means inherit")
	must(fs.Parse(args))
	if *issuerSKPath == "" || *subjectPKPath == "" || *outPath == "" {
		must(errors.New("missing --issuer-sk, --subject-pk, or --out"))
	}
	issuerSK, err := os.ReadFile(*issuerSKPath)
	must(err)
	if len(issuerSK) != ed25519.PrivateKeySize {
		must(fmt.Errorf("bad issuer sk length: got %d want %d", len(issuerSK), ed25519.PrivateKeySize))
	}
	issuerPK := ed25519.PrivateKey(issuerSK).Public().(ed25519.PublicKey)

	subjectPK, err := os.ReadFile(*subjectPKPath)
	must(err)
	if len(subjectPK) != ed25519.PublicKeySize {
		must(fmt.Errorf("bad subject pk length: got %d want %d", len(subjectPK), ed25519.PublicKeySize))
	}

	flags := byte(0)
	if *canIssue {
		flags |= 0x01
	}

	if *allowDomains != "" && *allowDomainsMask != "" {
		must(errors.New("cannot use both --allow-domains and --allow-domains-mask"))
	}
	var allowMask uint64 = 0
	if *allowDomains != "" {
		m, err := parseAllowDomainsCSV(*allowDomains)
		must(err)
		allowMask = m
	} else if *allowDomainsMask != "" {
		m, err := parseU64(*allowDomainsMask)
		must(err)
		allowMask = m
	}

	// Rolling: issue OREN_CERT v2 by default (adds allow_domains_mask field).
	bodyNoSig := buildCertV2BodyNoSig(flags, issuerPK, subjectPK, allowMask)
	bodyHash := sha256.Sum256(bodyNoSig)
	sig := ed25519.Sign(ed25519.PrivateKey(issuerSK), bodyHash[:])
	cert := append(bodyNoSig, sig...)

	must(os.WriteFile(*outPath, cert, 0o644))
	fmt.Println("Wrote cert:", *outPath)
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
