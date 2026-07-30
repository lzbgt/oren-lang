#!/usr/bin/env python3
"""CLI wrapper for the native IR LLVM lowerer implementation."""

import sys

from native_ir_llvm_lower_impl import main


if __name__ == "__main__":
    main(sys.argv)
