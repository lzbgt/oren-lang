# Project Notes

**Last updated:** 2026-05-31

`project-doc/` contains focused dated notes that still affect engineering decisions.
Canonical current docs live in `docs/`.

## Current Notes

- `current_implementation_20260526.md` - compact current implementation map.
- `ios_avm_sdk_design_20260531.md` - iOS host-adapter SDK design for libavm, compiler-in-AVM, and default FS/NET/PROC/TIME/GFX adapters.
- `avm_ios_graphics_design_20260529.md` - AVM-to-iOS graphics command-buffer and Metal host design.
- `avm_ui_render_performance_design_20260531.md` - high-refresh/high-resolution UI render contract for the AVM-host boundary.
- `obc_store_distribution_design_20260529.md` - public signed OBC package/store design for iOS app experiences.
- `obc_store_service_design_20260601.md` - `store.hubstack.cn` Go registry/API service design for OBC publishing, search, download, and install flows.
- `obc_store_trust_tooling_20260601.md` - external trust/key tooling for OBC store host apps.
- `web/3mf/README.md` - saved 3MF core specification reference for Scene3D package asset lowering.
- `ios_avm_readiness_20260507.md` - AVM/iOS production readiness inspection.
- `yield_coroutine_lowering_20260422.md` - current yield/generator/coroutine boundary.
- `repo_inspection_20260404.md` - current repo map.
- `review_20260408_production_readiness.md` - retained production readiness review conclusion.
- `rolling_cleanup_notes_20260506.md` - short list of retained/rejected cleanup conclusions.

Avoid adding large rolling transcripts here. Keep raw evidence in `build/logs/`.
