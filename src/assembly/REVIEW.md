# Assembly Review: Linux & Pico

Reviewed: 2026-03-01

## Overview

Both assemblies demonstrate Adamant's component-based architecture on two targets: native Linux (desktop/Docker) and bare-metal Raspberry Pi Pico (RP2040). They share ~80% of the same component set and wiring patterns, differing mainly in I/O interfaces, resource sizing, and a few platform-specific features.

---

## 1. Assembly YAML Structure Comparison

### Shared Components (both assemblies)
| Subsystem | Components |
|---|---|
| **Time** | `Gps_Time` (System_Time_Instance) |
| **Rate Groups** | `Ticker` → `Tick_Divider` → `Slow_Rate_Group` (0.5 Hz), `Fast_Rate_Group` (5 Hz), `Watchdog_Rate_Group` (1 Hz) |
| **Commands** | `Ccsds_Command_Depacketizer`, `Command_Router` |
| **Events** | `Event_Filter`, `Event_Limiter`, `Event_Packetizer` |
| **Telemetry** | `Product_Database`, `Product_Packetizer`, `Ccsds_Packetizer` |
| **Mission** | `Counter`, `Oscillator_A`, `Oscillator_B` |
| **Fault Protection** | `Zero_Divider`, `Task_Watchdog`, `Fault_Producer`, `Fault_Correction` |
| **Monitoring** | `Cpu_Monitor`, `Queue_Monitor`, `Stack_Monitor` |

### Linux-Only Components
- **`Event_Text_Logger`** — prints human-readable events to terminal (priority 1, async queue 1024)
- **`Event_Splitter_Instance`** (×2) — splits event stream into filtered/limited + post-mortem paths
- **`Event_Post_Mortem_Logger`** — 100 KB circular buffer on heap for post-mortem event log
- **`Memory_Packetizer`** — dumps post-mortem log on command
- **`Ccsds_Socket_Interface`** — TCP/IP to `host.docker.internal:2003`
- **`Interrupt_Servicer`** + **`Interrupt_Responder`** — SIGUSR1 interrupt handling
- **`Parameters`**, **`Parameter_Store`**, **`Parameter_Manager`** — full parameter table system
- **`Memory_Map`** package — static byte array backing the parameter store

### Pico-Only Components
- **`Ccsds_Serial_Interface`** — UART serial (115200 baud) with sync pattern `0xFED4AFEE`
- **`Adc_Data_Collector`** — reads RP2040 ADC (Channel 0, Vsys, Temperature)

### Pico Notably Missing
- No event text logger (no terminal)
- No event splitter / post-mortem logger / memory packetizer (RAM-constrained)
- No parameter system (oscillator parameters are wired to `ignore`)
- No interrupt servicer/responder (commented out with `#`)

---

## 2. Task Configuration & Priorities

### Linux
| Task | Priority | Stack | Sec. Stack |
|---|---|---|---|
| Ticker | 10 | 50 KB | 10 KB |
| Fault_Correction | 11 | 40 KB | 5 KB |
| Watchdog_Rate_Group | 10 | 50 KB | 10 KB |
| Slow/Fast_Rate_Group | 9 | 50 KB | 10 KB |
| Command_Router | 8 | 50 KB | 10 KB |
| Ccsds_Socket_Interface | 6 | 50 KB | 10 KB |
| Parameters / Param_Store / Param_Manager | 3 | 30-40 KB | 5 KB |
| Event_Text_Logger | 1 | 50 KB | 10 KB |
| Memory_Packetizer | 1 | 50 KB | 10 KB |
| Interrupt_Servicer | 1 | 20 KB | 10 KB |

### Pico
| Task | Priority | Stack | Sec. Stack |
|---|---|---|---|
| Fault_Correction | 11 | 4 KB | 100 B |
| Ticker / Watchdog_Rate_Group | 10 | 2-3 KB | 100 B |
| Slow_Rate_Group | 9 | 15 KB | 100 B |
| Fast_Rate_Group | 9 | 10 KB | 100 B |
| Command_Router | 8 | 5 KB | 100 B |
| Ccsds_Serial_Interface | 1 | 2 KB | 100 B |
| Serial Listener (subtask) | **0** | 2 KB | 100 B |

**Observation:** Pico stacks are ~10-25× smaller. The serial listener at priority 0 spins on the UART without sleeping — documented as intentional since it must not starve but also must not block higher-priority work. Priority ordering is consistent across both: Fault_Correction > Ticker/Watchdog > Rate Groups > Command Router > I/O.

---

## 3. Rate Group Wiring (Tick Divider)

Both use identical dividers: `[1 => 5, 2 => 10, 3 => 1]`
- Divider output 1 (÷5 = 1 Hz) → **Watchdog_Rate_Group**
- Divider output 2 (÷10 = 0.5 Hz) → **Slow_Rate_Group**
- Divider output 3 (÷1 = 5 Hz) → **Fast_Rate_Group**

Ticker period is 200 ms (5 Hz base) on both.

### Slow Rate Group Schedule (8 slots)
| Index | Linux | Pico |
|---|---|---|
| 1 | Counter | Counter |
| 2 | Event_Packetizer | Event_Packetizer |
| 3 | Cpu_Monitor | Cpu_Monitor |
| 4 | Queue_Monitor | Queue_Monitor |
| 5 | Stack_Monitor | Stack_Monitor |
| 6 | Event_Filter | Event_Filter |
| 7 | Event_Limiter | Event_Limiter |
| 8 | **Parameter_Manager** (timeout tick) | **Adc_Data_Collector** |

### Fast Rate Group Schedule (3 slots) — identical
1. Oscillator_A → 2. Oscillator_B → 3. Product_Packetizer

### Watchdog Rate Group (1 slot) — identical
1. Task_Watchdog

---

## 4. Event Pipeline Architecture

### Linux (complex, two-stage split)
```
All event sources → Event_Splitter_Instance
  ├─[1] → Event_Filter → Event_Limiter → Event_Splitter_2
  │         ├─[1] → Event_Packetizer (downlink)
  │         └─[2] → Event_Text_Logger (terminal, async)
  └─[2] → Event_Post_Mortem_Logger (unfiltered)
```

### Pico (simplified linear)
```
All event sources → Event_Filter → Event_Limiter → Event_Packetizer (downlink)
```

No splitter, no post-mortem log, no text logger. Events from `Ccsds_Serial_Interface` are pre-disabled in the Event_Limiter via `Event_Disable_List`.

---

## 5. Command Routing

Linux: 22 command destinations. Pico: 17 command destinations.

The delta accounts for components only present in Linux: Event_Post_Mortem_Logger, Memory_Packetizer, Parameters, Parameter_Store, Parameter_Manager.

Both route fault correction commands via the **synchronous** `Command_T_To_Route_Recv_Sync` connector on the Command_Router, bypassing its queue for fastest/most reliable fault response execution. This is well-documented in the connection description.

---

## 6. Fault Protection

### Fault Responses (identical across both)
| Fault | Latching | Response |
|---|---|---|
| Task_Watchdog.Slow_Rate_Group_Fault | Yes | Noop_Arg(1) |
| Task_Watchdog.Fast_Rate_Group_Fault | Yes | Noop_Arg(2) |
| Fault_Producer.Fault_1 | No | Noop_Arg(3) |
| Fault_Producer.Fault_2 | No | Noop_Arg(4) |

### Task Watchdog (identical config)
- Slow_Rate_Group: limit=3, error_fault, fault_id=1
- Fast_Rate_Group: limit=3, error_fault, fault_id=2
- Watchdog_Rate_Group pet → `ignore` (implicit monitoring since watchdog runs on this group)
- Task_Watchdog hardware pet → `ignore` (no HW watchdog connected in either assembly)

**Observation:** The Pico's `critical: False` on both watchdog entries means the HW watchdog (if connected) would continue being serviced even during a rate group fault. The comment says "Make True to stop servicing downstream HW watchdog" — this is a conscious design choice for the example but would likely be `True` in a real mission.

### Pico-specific: Zero_Divider
Has `Sleep_Before_Divide_Ms => 2200` and `Packet_Id_Base => 97` — gives time for the fault event to be downlinked on the 2-second rate group before the divide-by-zero crashes the processor. Linux version has neither (no need — Linux handles the exception).

---

## 7. Parameter System (Linux Only)

Parameters managed for 6 values: Oscillator_A (Frequency, Amplitude, Offset) and Oscillator_B (same).

Architecture:
- **Parameters** (active table) ↔ **Parameter_Manager** ↔ **Parameter_Store** (default table in `Memory_Map`)
- `Memory_Map.ads` allocates a static byte array sized to `Parameter_Table_Size_In_Bytes`
- Bidirectional memory region exchange via `Parameters_Memory_Region_T` / `Parameters_Memory_Region_Release_T`
- `Dump_Parameters_On_Change => True` for both active and default stores
- `Ticks_Until_Timeout => 3` on Parameter_Manager (timeout via Slow_Rate_Group slot 8)

On Pico, the oscillator `Parameter_Update_T_Modify` connectors are wired to `ignore` — parameters are compile-time only.

---

## 8. I/O Interface Differences

### Linux: TCP Socket
- `Ccsds_Socket_Interface` connects to `host.docker.internal:2003`
- Queue size: 8192 bytes
- Listener subtask at priority 0
- Bidirectional: uplink (CCSDS packets → Command_Depacketizer) and downlink (CCSDS packets from Packetizer)

### Pico: UART Serial
- `Ccsds_Serial_Interface` with `Interpacket_Gap_Ms => 0`
- Queue size: `4 * Ccsds_Space_Packet.Size_In_Bytes`
- Sync pattern `0xFED4AFEE` for framing
- Listener subtask at priority 0 (spins on UART)
- Same bidirectional flow but over serial

### Ground System Config
Both support COSMOS (OpenC3) and Hydra. Linux uses TCP (`tcpip_server_interface`), Pico uses serial (`serial_interface`) with CRC sync protocol. Pico also provides a `plugin.txt.for_mac` variant using TCP for Mac/Windows hosts that can't passthrough serial to Docker (requires `serial_tcp_bridge.py`).

---

## 9. Initialization Sequence

### Linux (`main/main.adb`)
```
1. Init_Base
2. Set_Id_Bases
3. Connect_Components
4. Init_Components
5. delay 1 second
6. Start_Components
7. Set_Up_Components
8. loop forever (500 ms delay)
```

Also has `Start_Up` package (elaborated before tasks via `pragma Elaborate_All`) that installs a task termination fallback handler to print exception info if any task dies. This is Linux-specific (`Ada.Task_Termination` has a different spec on Ravenscar/embedded).

### Pico (`main/main.adb`)
```
1. RP.Clock.Initialize (12 MHz XOSC)
2. RP.Clock.Enable (PERI)
3. Pico_Uart.Initialize
4. Init_Base ... Set_Up_Components (same sequence)
5. loop forever (500 ms delay)
```

No task termination handler (Ravenscar profile). Lots of commented-out debug `Put_Line` calls and LED toggle — useful development breadcrumbs.

---

## 10. Observations & Potential Issues

### Good Patterns
1. **Consistent priority scheme** across both assemblies — easy to reason about scheduling.
2. **Fault correction bypasses command queue** via sync connector — correct for safety-critical path.
3. **Event pipeline gracefully degrades** — Pico drops post-mortem and text logging but keeps filter+limiter+packetizer.
4. **Identical fault response tables** — behavior parity between development (Linux) and target (Pico).
5. **Well-commented YAML** — descriptions on most connections and components.

### Potential Concerns
1. **Pico has no post-mortem logging** — if the system crashes, there's no event record. The `Zero_Divider` sleep workaround is clever but fragile. Consider even a small circular buffer in a `.noinit` RAM section.
2. **Pico parameters wired to `ignore`** — oscillator tuning requires reflash. A minimal parameter system or command-based frequency setting would help in-flight.
3. **HW watchdog not connected on Pico** (`Pet_T_Send → ignore`) — for a real deployment, this should connect to the RP2040 watchdog peripheral. The `critical: False` setting compounds this.
4. **Pico serial listener at priority 0 busy-waits** — acceptable for a demo but would burn CPU on a multi-core system or when power matters.
5. **Linux socket hardcoded to `host.docker.internal`** — won't work outside Docker. Could be made configurable via init parameter or environment variable.
6. **Linux Event_Text_Logger queue = 1024 bytes** (not elements) — could drop events under burst if event serialized size is large. Other queues use `N * Get_Max_Queue_Element_Size` pattern; this one doesn't.
7. **Command_Router queue sizes differ** — Linux uses `10 *`, Pico uses `5 *`. The Pico's smaller queue could drop commands under fault-storm scenarios where fault correction injects commands rapidly.
8. **Pico assembly has no `parameter_table.yaml`** — consistent with no parameter system, but the file's absence means the build system must handle this gracefully.
9. **Commented-out interrupt system in Pico** — left as YAML comments rather than removed. Suggests planned future use (GPIO interrupts on `IO_IRQ_BANK0_Interrupt_CPU_1`) but currently dead code that adds confusion.

### Minor Nits
- `linux_example.product_packets.yaml` comment says `period: "1" # create every 3 ticks` for Housekeeping_Packet — the comment contradicts the value.
- Hydra setup scripts reference `../../../../../../adamant/` as a relative path — fragile if repo layout changes.
- `Event_Post_Mortem_Logger` spelled "Mortum" in hydra hardware.xml (`eventPostMortumFile`) — should be "Mortem".
