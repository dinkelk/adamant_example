# Interrupt Responder — Component Review

**Date:** 2026-03-01
**Scope:** `src/components/interrupt_responder/` and sub-package `interrupt_action/` (linux/, pico/)

---

## Overview

A **passive** Adamant component that receives a synchronous tick and delegates to a platform-specific `Interrupt_Action.Do_Action` procedure. It has three connectors: a `Tick.T` recv_sync invokee, an `Event.T` send connector, and a `Sys_Time.T` getter. One event (`Interrupt_Received`) is defined.

## File Summary

| File | Purpose |
|------|---------|
| `interrupt_responder.component.yaml` | Component model: passive, 3 connectors |
| `interrupt_responder.events.yaml` | Defines `Interrupt_Received` event (param: `Tick.T`) |
| `*-implementation.ads` | Instance type (empty record), overrides `Tick_T_Recv_Sync` |
| `*-implementation.adb` | Calls `Interrupt_Action.Do_Action(Arg)` on tick |
| `interrupt_action.ads` | Platform-neutral spec: `Do_Action(Tick.T)` with `Elaborate_Body` |
| `interrupt_action/linux/*.adb` | Prints tick to stdout via `Ada.Text_IO` |
| `interrupt_action/pico/*.adb` | No-op stub (body is `null`) |
| `interrupt_action/pico/env.py` | Selects pico build environment |
| `doc/interrupt_responder.tex` | LaTeX design doc template (pulls from build/ artifacts) |

## Findings

### 1. Event connector declared but never used
The component YAML defines an `Event.T` send connector and `interrupt_responder.events.yaml` defines `Interrupt_Received`, but the implementation body **never sends this event**. `Tick_T_Recv_Sync` only calls `Interrupt_Action.Do_Action`; it never invokes `Self.Event_T_Send_...`. Either the event should be emitted or the connector/event definition is dead code.

### 2. Sys_Time getter connector unused
A `Sys_Time.T` get connector is declared in the component YAML but is never referenced in the implementation. Same concern as above — dead interface or incomplete implementation.

### 3. `Self` unused in `Tick_T_Recv_Sync`
The body creates `Ignore : Instance renames Self` to suppress the unused warning. This is consistent with Adamant conventions but reinforces that the component does nothing with its own state or connectors — it's purely a pass-through to the free-standing `Interrupt_Action` package.

### 4. Pico implementation is a no-op
The Pico body does nothing (`null`). Commented-out `Ada.Real_Time` import suggests intended timing logic that was never completed. If this is intentional placeholder code, a comment explaining why would help.

### 5. `in` mode mismatch between spec and Pico body
The spec declares `The_Tick : in Tick.T` but the Pico body omits the explicit `in` keyword (`The_Tick : Tick.T`). This is semantically identical in Ada (parameters are `in` by default) but inconsistent style.

### 6. No unit tests present
No test files found outside `build/`. The LaTeX doc references a unit test section but it pulls from build artifacts. Unclear if tests exist elsewhere in the tree.

### 7. `Event_T_Send_Dropped` handler is null
The dropped-event handler is `is null`. Given that events aren't sent at all (finding #1), this is moot, but if events are added it should be revisited.

## Recommendations

1. **Either emit `Interrupt_Received` events** in `Tick_T_Recv_Sync` (using `Self` and the event/sys_time connectors) **or remove the dead connectors/event YAML** to keep the interface honest.
2. **Complete or document** the Pico stub — add a comment or TODO explaining the no-op.
3. **Unify parameter style** (`in` keyword) across platform bodies for consistency.
4. **Add or reference unit tests** for this component.
