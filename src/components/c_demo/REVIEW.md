# C_Demo Component Review

**Date:** 2026-03-01
**Scope:** `src/components/c_demo/` — all files excluding `build/`

---

## Overview

C_Demo is a **passive Adamant component** that demonstrates integrating a C library into the Ada/Adamant component framework. On each scheduled tick it calls a C `increment` function, wraps the result in an event, and sends it out.

## Architecture

```
Tick (recv_sync) ──► C_Demo ──► Event (send)
                       │
                       └──► Sys_Time (get)
```

The component holds a `c_data` record (count + limit) initialized to `{count=0, limit=3}`. Each tick increments count via the C library; when count exceeds limit, it wraps to 0.

## File-by-File Analysis

### Component Core

| File | Purpose |
|------|---------|
| `c_demo.component.yaml` | Declares passive component with 3 connectors (Tick recv, Event send, Sys_Time get) |
| `c_demo.events.yaml` | Single event `Current_Count` carrying `Packed_U32.T` |
| `component-c_demo-implementation.ads` | Spec — Instance record with `My_C_Data`, null `Set_Up`, null `Event_T_Send_Dropped` |
| `component-c_demo-implementation.adb` | Body — `Tick_T_Recv_Sync` calls C `increment`, emits `Current_Count` event |

### C Library (`c_lib/`)

| File | Purpose |
|------|---------|
| `c_lib.h` | Defines `c_data` struct and `increment` prototype |
| `c_lib.c` | Implements `increment`: if count < limit, add 1 via `c_dep`; else reset to 0 |
| `c_lib_h.ads` | Ada binding (generated via `-fdump-ada-spec` style) importing `c_data` and `increment` |
| `c_dep/c_dep.h` | Declares `add_1` helper |
| `c_dep/c_dep.c` | Implements `add_1(value)` → `value + 1` |

### Tests (`test/`)

| File | Purpose |
|------|---------|
| `test.adb` | AUnit test runner entry point |
| `tests.c_demo.tests.yaml` | Test suite descriptor — one test: `Test_C` |
| `tests-implementation.ads/adb` | Test body — sends 4 ticks, asserts count sequence 1→2→3→0 |
| `component-c_demo-implementation-tester.ads/adb` | Auto-generated tester harness with history buffers for events/connectors |
| `env.py` | Build environment import |

## Findings

### Strengths

1. **Clean FFI pattern.** The C→Ada binding is well-structured: C library with header, Ada spec with `Convention => C`, component using `'Access`. Good reference example.
2. **Proper layered C dependency.** `c_lib` depends on `c_dep`, demonstrating nested C dependencies work in the build system.
3. **Thorough test coverage.** The test exercises the full wrap-around cycle (1→2→3→0), verifying both the increment and reset paths.
4. **Minimal component.** Does one thing, cleanly. Good pedagogical value.

### Observations / Minor Issues

1. **`Event_T_Send_Dropped` is null.** Acceptable for a demo, but in production a dropped event should at minimum log a warning or increment a fault counter.
2. **No overflow protection in `add_1`.** If `value` is `UINT_MAX`, `add_1` silently wraps. Not reachable given the limit check in `increment`, but the C function itself is unguarded.
3. **Hardcoded init values.** `count => 0, limit => 3` is baked into the record default. A discriminant or init parameter would make the component reusable, though for a demo this is fine.
4. **Ada binding appears hand-maintained.** The `c_lib_h.ads` has `pragma Style_Checks (Off)` suggesting auto-generation, but it lives in source control. If the C header changes, the binding must be manually regenerated. A comment noting the generation command would help.
5. **Test uses hardcoded tick timestamps.** `(Time => (1, 1), Count => ...)` — fine for unit tests but worth noting that time progression isn't tested.

### No Defects Found

The logic is correct. The count sequence 0→1→2→3→0→1… matches the implementation (increment when < limit, reset otherwise). The Ada binding faithfully mirrors the C interface.

## Verdict

**Well-written demo component.** Serves its purpose as a clear, minimal example of C library integration in Adamant. No bugs, clean structure, adequate tests. The observations above are minor and appropriate to flag for production hardening but not issues for a demo.
