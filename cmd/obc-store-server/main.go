package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"

	"oren/internal/obcstore"
)

func main() {
	addr := flag.String("addr", ":8080", "HTTP listen address")
	dataDir := flag.String("data-dir", "build/obc-store", "store data directory")
	indexSigningKey := flag.String("index-signing-key", os.Getenv("OBC_STORE_INDEX_SIGN_KEY_PEM"), "optional P-256 private key PEM for /api/v0/index.json.sig")
	flag.Parse()

	adminUser := os.Getenv("OBC_STORE_ADMIN_USERNAME")
	adminPassword := os.Getenv("OBC_STORE_ADMIN_PASSWORD")
	adminTokenHash := os.Getenv("OBC_STORE_ADMIN_TOKEN_SHA256_HEX")
	svc, err := obcstore.New(obcstore.Config{
		DataDir:                *dataDir,
		AdminUser:              adminUser,
		AdminPassword:          adminPassword,
		AdminTokenSHA256Hex:    adminTokenHash,
		IndexSigningKeyPEMPath: *indexSigningKey,
	})
	if err != nil {
		log.Fatalf("failed to initialize OBC store: %v", err)
	}

	fmt.Fprintf(os.Stderr, "obc-store-server listening on %s\n", *addr)
	if err := http.ListenAndServe(*addr, svc.Handler()); err != nil {
		log.Fatal(err)
	}
}
