# Cpp_Demo Component Review

**Date:** 2026-03-01  
**Scope:** `src/components/cpp_demo/` and all sub-packages (excluding `build/`)

---

## Overview

Cpp_Demo is a **passive Adamant component** demonstrating C++ library integration within the Ada/Adamant framework. On each tick it increments a C++ `Counter` object and emits the current count as an event. The counter rolls over to zero when a configurable limit is reached.

**Architecture:**
```
cpp_demo (Ada component)
  └── cpp_lib (C++ Counter class, Ada binding)
        └── cpp_dep (C++ Container class, Ada binding)
```

---

## File-by-File Review

### 1. Component Definition

#### `cpp_demo.component.yaml`
- Clean, minimal YAML defining a passive component with `Tick.T` recv_sync, `Event.T` send, and `Sys_Time.T` get connectors.
- **No issues.**

#### `cpp_demo.events.yaml`
- Defines one event: `Current_Count` with `Packed_U32.T` parameter.
- ⚠️ **Minor:** Description says "Events for the **c_demo** component" — should be "cpp_demo".

### 2. Component Implementation

#### `component-cpp_demo-implementation.ads`
- Declares the private `Instance` record containing an `aliased cpp_lib_hpp.Class_Counter.Counter`.
- `Set_Up` and `Event_T_Send_Dropped` are null-overridden — appropriate for this demo.
- **No issues.**

#### `component-cpp_demo-implementation.adb`
- `Init`: Calls `Counter.initialize` with initial count 0 and the user-supplied limit.
- `Tick_T_Recv_Sync`: Increments counter, sends count as an event via `Event_T_Send_If_Connected`.
- Uses `Interfaces.C.unsigned` conversions correctly.
- **No issues.** Clean and straightforward.

### 3. C++ Library (`cpp_lib/`)

#### `cpp_lib.hpp` / `cpp_lib.cpp`
- `Counter` class with `count`, a `Container limit` member, `initialize()`, and `increment()`.
- Increment logic: if `count < limit` then increment, else reset to 0. Returns the new count.
- ⚠️ **Bug (minor):** `count` is uninitialized by the default constructor. Until `initialize()` is called, `count` holds indeterminate value. The Ada side calls `Init` before use, so this is safe in practice, but the C++ class is not self-contained.
- ⚠️ **Design note:** `increment()` returns the count *after* modification. When count equals limit, it resets to 0 and returns 0. This means the counter cycles through values `1, 2, ..., limit, 0, 1, ...` — value 0 appears but the initial value after first tick is 1. This is consistent with the test expectations.

#### `cpp_lib_hpp.ads` (Ada binding)
- Auto-generated thin binding using `Convention => CPP` and mangled names.
- Record layout mirrors the C++ class (`count`, `limit`).
- **No issues.** Hardcoded paths in comments are cosmetic only.

### 4. C++ Dependency (`cpp_lib/cpp_dep/`)

#### `cpp_dep.hpp` / `cpp_dep.cpp`
- Simple `Container` class wrapping a single `unsigned int value` with `get()`/`set()`.
- ⚠️ **Bug (minor):** Constructor does not initialize `value`. Same pattern as above — relies on caller to `set()` before `get()`.
- Missing header guard / `#pragma once` in `cpp_dep.hpp`. Works here because only one includer, but not best practice.

#### `cpp_dep_hpp.ads` (Ada binding)
- Auto-generated, correct. Exposes `value` field directly (matches C++ memory layout).

### 5. Test Suite (`test/`)

#### `tests.cpp_demo.tests.yaml`
- Defines one test: `Test_Cpp`.

#### `test.adb`
- Standard AUnit runner with ANSI color output and termination handler. Boilerplate.

#### `tests-implementation.ads` / `tests-implementation.adb`
- `Set_Up_Test`: Allocates heap, connects tester, inits component with `Limit => 3`, calls `Set_Up`.
- `Test_Cpp`: Sends 4 ticks, verifying counts of 1, 2, 3, then rollover to 0. Validates both event emission count and payload value.
- **Test is correct and thorough** for the single behavior. Covers the full cycle including rollover.
- ⚠️ **Minor:** Ticks 3 and 4 use `Count => 2` instead of incrementing — this is fine (the tick count field isn't used by the component) but could be slightly misleading to readers.

#### `component-cpp_demo-implementation-tester.ads` / `.adb`
- Standard Adamant auto-generated tester harness. Wires connectors, provides history queues, dispatches events.
- **No issues.**

#### `env.py`
- Single-line environment import. Standard.

---

## Summary

| Category | Status |
|----------|--------|
| Functionality | ✅ Correct — counter increments and rolls over as designed |
| Ada/C++ interop | ✅ Bindings are correct and match class layouts |
| Test coverage | ✅ Full cycle tested (increment through rollover) |
| Code quality | ✅ Clean, well-structured, follows Adamant conventions |

### Issues Found

| # | Severity | Description |
|---|----------|-------------|
| 1 | Cosmetic | `cpp_demo.events.yaml` description says "c_demo" instead of "cpp_demo" |
| 2 | Low | `Container` and `Counter` default constructors leave member variables uninitialized |
| 3 | Low | `cpp_dep.hpp` missing include guard |
| 4 | Cosmetic | Test tick `Count` field values are inconsistent (1, 2, 2, 2) — not a bug but could confuse readers |

**Overall:** Well-written demo component. The C++ integration pattern (class → Ada thin binding → component usage) is clean and serves as a good reference. The identified issues are all minor/cosmetic.
