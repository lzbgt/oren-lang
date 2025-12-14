#!/bin/bash
set -e

# 1. Create mylib.oren
cat > mylib.oren <<EOF
fn lib_hello() {
    print("Hello from Oren Lib!")
    return 42
}
EOF

# 2. Build Shared Library
echo "Building mylib.dylib..."
./oren build mylib.oren --backend native --lib -o mylib.dylib

# 3. Check Header
if [ -f mylib.h ]; then
    echo "Header generated."
else
    echo "FAIL: No header generated."
    exit 1
fi

# 4. Scan Library
echo "Scanning mylib.dylib..."
./oren scan mylib.dylib

# 5. Link with C
cat > test_link.c <<EOF
#include <stdio.h>
#include "mylib.h"

int main() {
    printf("Calling lib_hello...\n");
    int64_t res = lib_hello();
    printf("Result: %lld\n", (long long)res);
    return 0;
}
EOF

echo "Compiling test_link.c..."
gcc -o test_link test_link.c mylib.dylib

echo "Running test_link..."
./test_link
