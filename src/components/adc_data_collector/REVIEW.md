# ADC Data Collector — Component Review

## Overview

A passive Adamant component for the Raspberry Pi Pico that periodically reads three ADC channels (GPIO channel 0, VSYS voltage, and on-chip temperature sensor) and publishes them as data products. Driven by a `Tick.T` schedule connector.

## Files Reviewed

| File | Purpose |
|------|---------|
| `adc_data_collector.component.yaml` | Component model — declares connectors (Tick recv, Data_Product send, Sys_Time get) |
| `adc_data_collector.data_products.yaml` | Defines three data products: Channel_0, Vsys, Temperature (all `Packed_Integer.T`) |
| `component-adc_data_collector-implementation.ads` | Ada spec — Instance type (empty extension), overrides for Tick handler; null Set_Up and dropped-DP handler |
| `component-adc_data_collector-implementation.adb` | Ada body — ADC reads + data product sends; elaboration-time ADC/GPIO init |
| `all.do` | Redo build file listing object targets |
| `doc/adc_data_collector.tex` | LaTeX design document template (pulls generated sections from build/) |
| `doc/env.py` / `env.py` | Both just `from environments import pico` |
| `.Pico_path` | Empty marker file (target selector) |

## Strengths

1. **Clean, minimal design.** The component does one thing well — no unnecessary state, no commands, no parameters. The instance record is `null`; all behavior is in a single tick handler.
2. **Good hardware hygiene.** SMPS power-save pin is toggled around ADC reads exactly as recommended by the Pico datasheet to reduce switching-regulator noise. The comment explains *why*.
3. **Proper Adamant patterns.** Passive execution, connector typing, data product generation with timestamps, elaboration-time HW init — all idiomatic.
4. **Self-documenting.** YAML descriptions are clear; Ada comments explain the non-obvious SMPS noise mitigation.

## Issues & Suggestions

### Medium

1. **No error handling on ADC reads.** `RP.ADC.Read_Microvolts` and `RP.ADC.Temperature` are called without any protection. If the ADC peripheral faults or returns an out-of-range value, the `Integer()` conversion could raise `Constraint_Error`. Consider adding range checks or a fault data product.

2. **`Data_Product_T_Send_Dropped` is silently null.** If the data product queue fills up (e.g., downstream consumer stalls), all three DPs are silently lost with no event or counter. Consider at minimum logging an event or incrementing a fault counter on drop.

3. **VSYS multiply-by-3 could overflow.** `Read_Microvolts(Pico.VSYS_DIV_3) * 3` — if the raw reading approaches the upper range of the return type, the `* 3` could overflow before the `Integer()` conversion. Verify the return type of `Read_Microvolts` has sufficient headroom, or perform the multiplication in a wider type.

### Low

4. **Duplicate object in `all.do`.** The file lists `adc_data_collector_data_products.o` twice. Harmless but sloppy — remove the duplicate.

5. **No unit tests present.** The LaTeX doc has a unit-test section (pulling from build/) but there is no test directory or test code in this component. Even for a hardware-dependent component, mock-based tests for the data-product-publishing logic would add value.

6. **`env.py` duplicated.** Both `env.py` and `doc/env.py` contain the identical one-liner. This is likely an Adamant convention, but worth confirming it's intentional and not a copy-paste artifact.

7. **Temperature units ambiguity.** The data product type is `Packed_Integer.T` described as "Celsius", but `RP.ADC.Temperature` likely returns a fixed-point or scaled value. Document the exact unit/scaling (e.g., milli-degrees? whole degrees?) so downstream consumers interpret it correctly.

## Architecture Notes

- **Execution model:** Passive — runs only when ticked. No internal task, no queue. Simple and deterministic.
- **Data flow:** Tick in → 3× Data_Product out. Stateless per invocation.
- **Hardware coupling:** Directly uses `RP.ADC` and `RP.GPIO` via `Pico` package. Not abstractable without a HAL layer, which is acceptable for a board-specific example project.

## Verdict

Well-written, idiomatic Adamant component suitable as an example. The main risk area is the lack of error handling around hardware reads (#1, #3). The silent drop handler (#2) should be addressed if this component is used in a production context.
