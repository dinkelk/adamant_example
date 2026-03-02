# Parameter Manager — Component Review

**Date:** 2026-03-01  
**Reviewer:** Automated (Claude)

## Overview

The Parameter Manager is an **active** Adamant component responsible for copying parameter tables between a "working" (RAM) and "default" (NVRAM) store on command. It acts as an orchestrator—issuing memory-region get/set requests to downstream parameter-storage components, waiting for synchronous responses, and handling timeouts and errors.

## Architecture

- **Single command:** `Copy_Parameter_Table` with a direction enum (`Default_To_Working` | `Working_To_Default`).
- **Connectors:** Async command receive, sync tick for timeout, sync memory-region release for responses, two send connectors for working/default stores, plus event/command-response/sys-time connectors.
- **Synchronization:** Uses a `Task_Synchronization.Wait_Release_Timeout_Counter_Object` plus a protected variable for the response. The tick connector increments a timeout counter; the release connector stores the response and signals the waiting task.
- **Temporary buffer:** Heap-allocated `Parameter_Bytes` sized to `Parameter_Table_Length`, used as an intermediate staging area for copies. Deliberately kept as a component field (not stack) so a timeout doesn't corrupt the stack.

## Strengths

1. **Clean separation of concerns.** The component only orchestrates copies; actual parameter storage is delegated to downstream components.
2. **Robust timeout handling.** Configurable tick-based timeout with proper reset/clear before each request prevents stale signals from causing false completions.
3. **Thorough error reporting.** Six distinct events cover start, finish, timeout, failure, invalid command, and dropped command cases.
4. **Defensive design.** The `.ads` documents the rationale for heap-allocated staging memory (timeout-safety). The race condition in `Parameters_Memory_Region_Release_T_Recv_Sync` is explicitly analyzed and shown to be benign given correct assembly design.
5. **Excellent test coverage.** Six unit tests cover: nominal default→working, nominal working→default, copy failure (multiple error statuses on both legs), timeout on both directions, full queue, and invalid command arguments.
6. **Well-documented YAML specifications.** Component, commands, events, requirements, tests, types, and enums are all cleanly defined.

## Issues & Recommendations

### Medium

| # | Issue | Location | Recommendation |
|---|-------|----------|----------------|
| 1 | **Description inconsistency.** The `.ads` description mentions "working, scratch, and default" tables, but the component only handles working and default—there is no scratch table. The `.component.yaml` description is correct. | `.ads` line 10 | Update the `.ads` comment to remove "scratch". |
| 2 | **Comment says "default" when it means "working".** `Copy_To_From_Working` contains the comment `-- Send the request to the default component.` | `.adb`, `Copy_To_From_Working` | Change comment to `-- Send the request to the working component.` |
| 3 | **Copy helper comments say "set request to working"** in `Copy_Working_To_Default`, but the operation is actually sending a set to *default*. | `.adb`, `Copy_Working_To_Default` | Fix comment: `-- Send a set request to default`. |
| 4 | **Dropped-handler bodies are null.** If the working or default memory region send is dropped, the component silently continues waiting for a response that will never come (eventually timing out). | `.ads` dropped handlers | Consider at minimum logging an event in `Working_Parameters_Memory_Region_Send_Dropped` and `Default_Parameters_Memory_Region_Send_Dropped`, or signaling the sync object to unblock the task immediately. |

### Low

| # | Issue | Location | Recommendation |
|---|-------|----------|----------------|
| 5 | **No CRC validation in this component.** The `Crc_16` package is imported and used only in the `Init` assertion for sizing. The component trusts downstream stores to validate CRCs. This is fine architecturally, but the import of `Crc_16` might mislead readers into thinking CRC checking happens here. | `.adb` with-clause | Add a clarifying comment, or remove the import if the size check can reference `Crc_16.Crc_16_Type'Length` via a constant. |
| 6 | **Test globals lack thread safety.** `Task_Send_Response`, `Task_Send_Timeout`, etc. are plain `Boolean` variables shared between the test task and the main test thread with no synchronization. The code acknowledges this. Acceptable for tests but fragile. | `parameter_manager_tests-implementation.adb` | Consider using atomic or protected variables for correctness under optimization. |
| 7 | **Hardcoded table size in tester.** The tester declares `Default`/`Working` as `Byte_Array (0 .. 99)` and `Init` uses `Parameter_Table_Length => 100`. A named constant would reduce duplication. | Tester `.ads` + test `.adb` | Extract a shared constant. |

### Nit

- `env.py` references `test_component_1`, `test_component_2`, and `test_assembly` directories that aren't present in the reviewed tree—presumably generated or located elsewhere during build.
- Requirements are minimal (two one-liners). They match the implementation but could benefit from timeout/error-handling requirements for traceability.

## Types Sub-Package

- **`parameter_manager_enums.enums.yaml`** — Clean two-value enum (`Default_To_Working`, `Working_To_Default`) with explicit values 0/1 and good descriptions.
- **`packed_parameter_table_copy_type.record.yaml`** — Single-field packed record wrapping the enum as `E8`. Straightforward.

No issues found in the types.

## Test Coverage Summary

| Test | What it covers |
|------|---------------|
| `Test_Nominal_Copy_Default_To_Working` | Happy path: default→working, verifies memory region operations, events, command response. |
| `Test_Nominal_Copy_Working_To_Default` | Happy path: working→default, same verification. |
| `Test_Copy_Failure` | Exercises `Parameter_Error`, `Crc_Error`, `Length_Error` on both first-leg and second-leg failures, both copy directions. |
| `Test_Copy_Timeout` | Timeout on both copy directions. |
| `Test_Full_Queue` | Verifies `Command_Dropped` event on queue overflow. |
| `Test_Invalid_Command` | Bad argument length triggers `Invalid_Command_Received` event and `Length_Error` response. |

Coverage is thorough for the component's scope.

## Verdict

**Well-implemented component.** The design is sound, the code is clean, and tests are comprehensive. The main action items are fixing a few misleading comments (issues #1–3) and considering non-silent behavior for dropped send handlers (#4).
