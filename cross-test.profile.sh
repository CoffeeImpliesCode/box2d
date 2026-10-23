# cross-test profile sourced from the package root.
# Uses the published Zig 0.16.0 Tier 1/2 target table.
# The harness selects matrix targets, paths and runners.
# Only variable assignments; the harness may source this file repeatedly.

# Static is the default; CROSS_BUILD_ARGS can select dynamic linkage.
# Run the package's test step; check is compile-only.
CROSS_BUILD_STEP=test

# Allow for the full suite, including DeterminismTest under QEMU.
CROSS_BUILD_TIMEOUT=3600

# Timeout applies per Zig test case, not per binary.
CROSS_TIMEOUT=1800
