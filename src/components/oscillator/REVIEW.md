# Oscillator Component Review

**Date:** 2026-03-01
**Scope:** `src/components/oscillator/` (main component + test sub-package, excluding build/)

---

## Overview

The Oscillator is a **passive** Adamant component that generates a sine wave signal: `offset + amplitude * sin(2π * frequency * t)`. It outputs the computed value as a data product on each tick. Frequency, amplitude, and offset are controllable via both **commands** and **parameters**.

## Architecture

### Connectors (from `oscillator.component.yaml`)

| Direction | Type | Kind |
|-----------|------|------|
| In | `Tick.T` | `recv_sync` |
| In | `Command.T` | `recv_async` |
| In/Out | `Parameter_Update.T` | `modify` |
| Out | `Command_Response.T` | `send` |
| Out | `Data_Product.T` | `send` |
| Out | `Event.T` | `send` |
| Get | `Sys_Time.T` | `get` |

The component is **passive** (no dedicated task); it executes in the caller's context on each tick.

### Commands

Three commands (`Set_Frequency`, `Set_Amplitude`, `Set_Offset`), all taking `Packed_F32.T`. Each updates the internal state directly and emits a corresponding event.

### Parameters

Three parameters mirror the commands (`Frequency`, `Amplitude`, `Offset`) with defaults of 0.175 Hz, 5.0, and 0.0 respectively. Parameters go through staging/validation/update lifecycle.

### Events

Six events covering value-set confirmations, dropped commands, invalid commands, and invalid parameters.

### Data Products

Single data product `Oscillator_Value` (`Packed_F32.T`) — the computed sine value.

---

## Implementation Analysis (`component-oscillator-implementation.adb`)

### Tick Handler (`Tick_T_Recv_Sync`)
1. Calls `Self.Update_Parameters` — applies any staged parameter updates.
2. Calls `Self.Dispatch_All` — drains the async command queue.
3. Lazy-initializes `Self.Epoch` on first tick.
4. Computes elapsed time via `Sys_Time.Arithmetic`, converts to `Short_Float`.
5. Evaluates `offset + amplitude * sin(2π * freq * t)`.
6. Sends result as a data product.

### Observations & Potential Issues

1. **Command/parameter dual-path inconsistency:** Commands (`Set_Frequency`, etc.) directly write to `Self.Frequency.Value` (the working copy), bypassing the parameter staging mechanism. This means a command-set value can be silently overwritten on the next `Update_Parameters` call if a staged value is pending. This is a design choice but could be surprising.

2. **Epoch initialization race:** The epoch is set on the first tick. If the first tick arrives with `Time = (0, 0)`, the epoch check `Self.Epoch = (0, 0)` will re-trigger every tick since the assignment also sets it to `(0, 0)`. Depending on how `Sys_Time.T` is used in practice this may be benign, but it's a latent edge case.

3. **`Short_Float` precision:** Using `Short_Float` (typically 32-bit IEEE 754) for time accumulation will lose precision as elapsed time grows. For long-running missions, the sine computation could degrade. Consider whether this is acceptable for the use case.

4. **`Dispatch_All` return value ignored:** The result of `Self.Dispatch_All` is assigned to `Ignore` — fine stylistically, but no telemetry on queue depth is emitted.

5. **Parameter validation is arbitrary:** `Validate_Parameters` rejects `Frequency = 999.0` as invalid. The comment acknowledges this is for example/testing purposes. In a real system this should validate meaningful constraints (e.g., Nyquist limit relative to tick rate).

6. **No range checking on commands:** The `Set_Frequency`, `Set_Amplitude`, `Set_Offset` command handlers accept any `Short_Float` value without validation (NaN, negative frequency, etc.).

7. **`Unused` variable pattern:** `Ignore : Instance renames Self` in `Validate_Parameters` and `Ignore : Natural` in `Tick_T_Recv_Sync` — standard Adamant pattern for suppressing unused warnings; no issue.

---

## Test Analysis

### Test Infrastructure

- **Tester** (`component-oscillator-implementation-tester.ads/adb`): Full reciprocal tester with history buffers (depth 100) for all connector types. Provides `Stage_Parameter`, `Fetch_Parameter`, `Update_Parameters` helper functions and a white-box accessor `Get_Component_Frequency`.
- **Test harness** (`test.adb`): Standard AUnit runner with ANSI color output and termination handler.
- **Build env** (`env.py`): Minimal — imports shared test environment.

### Test Cases (from `oscillator.tests.yaml` and implementation)

| Test | What it covers |
|------|---------------|
| `Test_Parameters` | Default values, stage/update lifecycle, fetch verification |
| `Test_Parameter_Validation` | Valid staging, validate operation, invalid value (999.0) rejection, update-after-validate, tick-driven parameter adoption |

### Test Coverage Gaps

1. **No tick/sine-wave output tests:** There are no tests verifying the actual oscillator output (the sine computation). The data product value is never asserted against expected mathematical results.

2. **No command tests:** None of the three commands (`Set_Frequency`, `Set_Amplitude`, `Set_Offset`) are tested. No verification of command dispatch, event emission on command execution, or command response.

3. **No dropped-command test:** `Command_T_Recv_Async_Dropped` behavior is untested despite the tester having `Expect_Command_T_Send_Dropped` infrastructure.

4. **No invalid-command test:** The `Invalid_Command` handler is untested.

5. **No epoch behavior test:** The first-tick epoch initialization logic is untested.

6. **No multi-tick time-series test:** No test sends multiple ticks with advancing timestamps to verify the waveform over time.

7. **Parameter validation test is thorough** for its scope — it correctly verifies the staging → validate → update → tick lifecycle and the 999.0 rejection path. This is the strongest test.

---

## Documentation (`doc/oscillator.tex`)

Standard Adamant component document template referencing auto-generated sections from `build/tex/`. Structure is complete and covers all standard sections (description, requirements, diagram, connectors, commands, parameters, events, data products, etc.).

---

## Summary

| Aspect | Rating | Notes |
|--------|--------|-------|
| **Design** | Good | Clean, well-structured passive component following Adamant conventions |
| **Implementation** | Good | Straightforward sine oscillator; minor edge cases noted above |
| **Test coverage** | **Weak** | Only parameter lifecycle tested; no functional/output tests, no command tests |
| **Documentation** | Good | Standard template, auto-generated content |
| **Code style** | Good | Consistent with Adamant patterns, well-commented |

### Recommended Actions

1. **High priority:** Add unit tests for commands and sine-wave output verification.
2. **Medium priority:** Add tests for dropped/invalid command paths and epoch initialization.
3. **Low priority:** Consider input validation on command arguments (NaN, negative freq, etc.).
4. **Low priority:** Evaluate `Short_Float` precision for long-duration operation scenarios.
