# FPGA-STM32 Signal Analyzer & Filter Characterization

![Verilog](https://img.shields.io/badge/Language-Verilog_HDL-blue.svg)
![C/C++](https://img.shields.io/badge/Language-C%2FC%2B%2B-green.svg)
![Platform](https://img.shields.io/badge/Platform-Intel_Cyclone_IV_E_%7C_STM32F407ZGT6-orange.svg)
![Status](https://img.shields.io/badge/Status-Functional_Prototype-brightgreen.svg)

## 📌 Project Overview
This repository contains the design and implementation of a heterogeneous signal analyzer and automated filter characterization system prototype, built upon an **Intel Cyclone IV E (EP4CE15F17)** FPGA and an **STM32F407ZGT6** MCU.

The system adopts a Hardware-Software Co-design architecture:
* **The FPGA (Data Plane)** acts as a deterministic hardware accelerator, handling DDS signal synthesis, ADC sampling synchronization, and real-time DSP (LUT-based magnitude/phase extraction).
* **The STM32 (Control Plane)** manages the system-level state machine, Human-Machine Interface (HMI) parsing, and executes advanced software-level pre-distortion algorithms to compensate for the analog front-end frequency response.

---

## ⚙️ Key Technical Highlights

### 1. FPGA Gateware (DSP Data Plane)
* **DDS Sweep & Sampling:** Generates precision swept-frequency stimulus signals via phase accumulators, strictly synchronized with the ADC for point-by-point frequency response acquisition.
* **LUT-based Coordinate Conversion:** Explores a memory-for-speed architectural trade-off in `coord_transform.v`. It implements $\sqrt{I^2+Q^2}$ and 4-quadrant `atan2` phase corrections natively using ROM look-up tables. The ROMs consume approximately 9 M9K blocks in total (4096×16-bit for `sqrt`, 256×16-bit for `atan`).
* **Hardware Filter Classifier:** Integrates a threshold-based state machine that analyzes magnitude roll-offs across frequency sweeps to automatically classify unknown networks (LPF / HPF / BPF / BRF).
* **Robust UART Link:** Implements a custom asynchronous receiver featuring 16x oversampling and center-aligned sampling, reducing the bit error rate in noisy environments.

### 2. STM32 Firmware (Control Plane)
* **Layered Architecture:** Decouples core logic into Application State Machine (`app.c`) → Board Support Packages (`bsp_fpga_control.c`, `bsp_hmi.c`) → Low-level HAL/DMA Drivers, promoting firmware maintainability.
* **AFE Gain Equalization:** A custom LUT combined with a linear interpolation engine (`lut_cal.c`) compensates for the high-frequency attenuation of the Analog Front-End (AFE) across the 100Hz–6kHz spectrum, ensuring flat stimulus amplitude.
* **Async Packet Framing:** Drives the FPGA using dense 47-byte binary frames while concurrently processing asynchronous ASCII commands from the HMI screen via **UART IDLE Interrupts + DMA double-buffering**, achieving reliable non-blocking data parsing with minimal interrupt overhead.

---

## 🚧 Known Limitations
The current RTL data-path has explicit room for synthesizability and precision optimizations:
1. **Divider Placeholder:** The DSP coordinate transformation path currently uses behavioral constructs (the `$past` system task) for delay matching. This is slated to be replaced with an `LPM_DIVIDE` hardware IP and explicit shift-register chains to ensure strict RTL synthesizability.
2. **Small-Signal Quantization Noise:** To achieve single-cycle LUT addressing, the squared magnitude is directly truncated (top 12 bits). This introduces noticeable quantization noise for small inputs. A planned optimization is the introduction of a **Leading Zero Detector (LZD)** for dynamic bit-shifting (Block Floating Point logic) to maximize dynamic range without increasing ROM depth.
3. **Data Flow Handshaking:** The DSP pipeline currently lacks global `valid/ready` handshake signals, relying entirely on static clock cycle delays. This poses potential timing risks that will be addressed in the next iteration.

---

## 📂 Repository Structure
```text
├── FPGA_Gateware/               # FPGA Logic Design (Quartus)
│   ├── src/                     # RTL Verilog Source Code
│   │   ├── top.v                # Top-Level Integration & FSM
│   │   ├── filter_analyzer.v    # Filter Classification Engine
│   │   ├── coord_transform.v    # LUT-based Rect2Polar (Contains behavioral divider placeholder)
│   │   ├── triangle_wave_generator.v 
│   │   ├── command_parser.v     # 47-byte Custom Packet Bus Flattener
│   │   └── uart_rx.v / uart_tx.v# 16x Oversampling UART Transceivers
│   ├── constraints/             
│   │   └── tim.sdc              # Synopsys Design Constraints (50MHz)
│   └── sim/                     
│       ├── tb_top.v             # Functional Testbench
│       └── dds_ip_model.m       # MATLAB NCO Simulation Model
│
└── STM32_Firmware/              # Microcontroller Source Code (Keil MDK)
    ├── Core/Src/                # STM32 HAL & Low-level Drivers (DMA, UART)
    └── Core/software/           # Application Logic
        ├── app.c                # 5-Stage Central Core FSM
        ├── lut_cal.c            # AFE Gain Compensation (LUT + Interpolation)
        ├── bsp_fpga_control.c   # Float-to-Fixed Point Conversion & Framing
        └── bsp_hmi.c            # HMI Serial Communication Parser
