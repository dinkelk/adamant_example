# Utility Packages Review

Reviewed: 2026-03-01

---

## 1. `last_chance_handler/linux/`

**Purpose:** Last-chance exception handler for Linux targets. Exports `__gnat_last_chance_handler` as a C-convention symbol that GNAT calls on unhandled exceptions. Walks raw memory at `Msg` address byte-by-byte to print the exception string and line number via `GNAT.IO`.

**Files:** `last_chance_handler.ads`, `last_chance_handler.adb`, `.Linux_path` (empty marker)

**Observations:**
- Clean, minimal implementation. Avoids secondary stack (good for a crash handler).
- The `Peek` helper overlays a `Character` at an arbitrary `System.Address` — correct but inherently unsafe. Acceptable here since we're already in a terminal error path.
- No `pragma No_Return` on the procedure, unlike the Pico variant. The body does return normally after printing. If GNAT expects `__gnat_last_chance_handler` to never return, this could cause undefined behavior. **Recommend adding `pragma No_Return` or an infinite loop at the end** to match the Pico variant's contract.
- No protection against `Msg` being a null/invalid address.

**Rating:** Good — simple and appropriate for a Linux debug target.

---

## 2. `last_chance_handler/pico/`

**Purpose:** Last-chance exception handler for the RP2040 Pico. On unhandled exception, it lights the LED, serializes exception data into a CCSDS telemetry packet, and continuously transmits it over UART in an infinite loop.

**Files:** `last_chance_handler.ads`, `last_chance_handler.adb`, `env.py`, `.Pico_path` (empty marker)

**Observations:**
- Substantially more complex than the Linux variant — packages the exception name, message, and (stubbed) stack trace into a `Packed_Exception_Occurrence` record, wraps it in a CCSDS packet with CRC-16, and sends it with a sync pattern.
- Stack trace capture is commented out (`Tracebacks` not working on Pico). `Stack_Depth_Count` is hardcoded to 0. The commented-out `Copy_Idx` variable is dead code — clean it up.
- The outer `No_Exceptions_Propagated` block silently swallows all exceptions (`when others => null`). This is intentional (we're already crashing) but worth a comment explaining why.
- The infinite transmit loop flashes the LED and increments the sequence count — good for diagnostics.
- APID 97 is hardcoded with a comment referencing `example.assembly.yaml`. If the assembly APID changes, this breaks silently. **Consider defining this as a named constant or pulling from a shared config.**
- `Form_Exception_Data` uses `Ada.Unchecked_Conversion` from `Character` to `Unsigned_8` — fine, standard practice.
- The `@ + 1` syntax (Ada 2022 target name) is used throughout — confirms the project targets Ada 2022.
- Many large blocks of commented-out code (tracebacks, `Put_Line` calls). **Recommend cleaning these up or moving to a separate notes file** to improve readability.

**Rating:** Solid for its purpose, but needs comment/dead-code cleanup.

---

## 3. `pico_util/adc/`

**Purpose:** Standalone Pico utility that reads ADC channels in a loop and prints microvolts (channel 0, VSYS) and temperature over UART every second.

**Files:** `main.adb`, `env.py`, `all.do`

**Observations:**
- Straightforward diagnostic/test program. Good use of `SMPS_PS` pin toggling per the Pico datasheet recommendation to reduce ADC noise during measurement.
- Uses `Pico_Uart` (from the uart package) for output — good reuse.
- The `'Image` attribute is used for output formatting — fine for a test utility but uses the secondary stack.
- Uses Unicode characters (`μv`, `°C`) in string literals — works if the UART receiver handles UTF-8, but could display garbled on some terminals. Minor concern.
- No error handling on ADC reads. Acceptable for a test utility.

**Rating:** Good — clean test utility, does what it says.

---

## 4. `pico_util/hello_pico/`

**Purpose:** Minimal "Hello, Pico!" program that blinks the LED and transmits a greeting over UART0. Includes a GPR project file for standalone Alire builds and a `program.sh` script for flashing via OpenOCD.

**Files:** `main.adb`, `hello_pico.gpr`, `env.py`, `all.do`, `program.sh`

**Observations:**
- This is a self-contained sanity-check project — its GPR file sets up the cross-compiler and runtime independently. The comment confirms it's for verifying the Alire environment.
- `main.adb` configures UART inline (duplicating the setup that `Pico_Uart.Initialize` does). This is intentional — it's meant to be standalone without depending on other project packages.
- `Test_Error` exception is declared but only raised if transmit fails. On a bare-metal target with no handler, this would hit the last chance handler.
- Commented-out `RP.Device.Timer.Enable` and `Timer.Delay_Milliseconds` lines suggest the author experimented with timer-based delays vs `delay until`. The `delay until` approach is cleaner for Ravenscar.
- `program.sh` uses `cmsis-dap` and targets `rp2040` — standard debug probe workflow.
- Minor: The comment `-- I don't know if the pull up is needed, but it doesn't hurt?` appears here and is copy-pasted into `pico_uart.adb`. **Recommend resolving this uncertainty** (pull-up on TX is unnecessary for UART but harmless).

**Rating:** Good — appropriate as an environment validation tool.

---

## 5. `pico_util/interrupts/`

**Purpose:** Demonstrates GPIO interrupt handling on the Pico. A button on GP9 triggers an interrupt that toggles the LED.

**Files:** `main.adb`, `handlers.ads`, `handlers.adb`, `env.py`, `all.do`, `.skip_style`

**Observations:**
- `Protected_Handler` uses `pragma Attach_Handler` to bind to `Io_Irq_Bank0_Interrupt_Cpu_1` at the highest interrupt priority. The handler simply toggles the LED.
- `main.adb` configures GP9 as input with pull-up and enables falling-edge interrupt, then enters an infinite `null` loop.
- Commented-out code references `RP.GPIO.Interrupts.Attach_Handler` — an alternative approach that was abandoned. The comment `-- debouncing is an exercise left to the reader` is honest.
- No debouncing means rapid toggling on a bouncy switch. Fine for a demo.
- `.skip_style` presumably exempts this from project style checks — likely because the casing conventions differ (`Rp.Gpio` vs `RP.GPIO`). Indeed, `main.adb` uses inconsistent casing (`Rp.Gpio`, `Rp.Clock` vs `Pico.Gp9`, `Pico.Led`). **Recommend fixing casing to match project conventions and removing `.skip_style`.**
- The `Handlers` instance is never explicitly declared in `main.adb` — the `with Handlers;` is sufficient since the protected type is elaborated at package level. Wait — actually `Handlers` declares a *type* (`Protected_Handler`), not an instance. **This looks like a bug: no instance of `Protected_Handler` is ever created, so the interrupt handler is never actually attached.** Unless elaboration of the type spec alone attaches it, which it does not for `Attach_Handler` — an object must exist. **This needs verification; the interrupt handler may not work as written.**

**Rating:** Incomplete — likely has a bug where the interrupt handler is never instantiated. Needs review and testing.

---

## 6. `pico_util/uart/`

**Purpose:** UART abstraction layer for the Pico. Provides two packages: `Pico_Uart` (low-level UART0 driver on GP16/GP17) and `Diagnostic_Uart` (higher-level byte-oriented wrapper used by the Adamant framework's CCSDS serial interface).

**Files:** `pico_uart.ads`, `pico_uart.adb`, `diagnostic_uart.ads`, `diagnostic_uart.adb`, `env.py`, `.Pico_path`, `README.md`

**Observations:**
- `Pico_Uart` is clean and well-documented. `Initialize` sets up GP16/GP17 at 115200/8N1. `Send_Byte_Array` and `Receive_Byte` use address overlays to convert between `Basic_Types.Byte_Array` and HAL's `UART_Data_8b`.
- `Receive_Byte` handles `Busy` (break condition) by returning without error — but **it returns an uninitialized value** in the `Busy` case since `Byte` is never assigned a meaningful value. This is a silent data corruption risk. **Recommend either retrying in a loop or returning a status/sentinel.**
- `Send_Byte_Array` uses `Timeout => 0` which per HAL convention means "no timeout" (block forever). Same for `Receive_Byte`. The spec documents the blocking behavior — good.
- The `pragma Warnings (Off/On, "overlay changes scalar storage order")` pairs are correct — byte arrays have no meaningful storage order.
- `Diagnostic_Uart` is a thin wrapper delegating to `Pico_Uart`. Its spec comments explain the relationship to the Adamant framework's default UART implementation and how to swap implementations. Well-documented.
- `README.md` is brief but helpful — explains the build path override.
- The `Test_Error` exception name is misleading in production code — it's a holdover from test/prototype origins. **Consider renaming to `Uart_Error` or similar.**

**Rating:** Good overall, but fix the `Receive_Byte` uninitialized return on `Busy` status.

---

## Summary

| Package | Status | Key Issues |
|---|---|---|
| `last_chance_handler/linux` | ✅ Good | Add `No_Return` / infinite loop |
| `last_chance_handler/pico` | ✅ Good | Clean up commented-out code; hardcoded APID |
| `pico_util/adc` | ✅ Good | Minor: Unicode in output strings |
| `pico_util/hello_pico` | ✅ Good | Standalone env-check tool, serves its purpose |
| `pico_util/interrupts` | ⚠️ Needs Fix | No instance of `Protected_Handler` created — interrupt likely never attached; inconsistent casing |
| `pico_util/uart` | ✅ Good | Fix `Receive_Byte` returning uninitialized data on `Busy`; rename `Test_Error` |

### Cross-Cutting Observations
- **Ada 2022 features** (`@` target name) used throughout — good, modern.
- **Build system** uses `redo` (`all.do` files) and `env.py` files that import a shared `pico` environment.
- **Code reuse**: `hello_pico` duplicates UART setup that exists in `pico_uart` — intentional for standalone use.
- **Commented-out code** is prevalent, especially in the Pico last-chance handler and interrupts packages. A cleanup pass would improve maintainability.
