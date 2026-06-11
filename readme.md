# Heterogeneous FPGA-ARM Signal Analyzer & Filter Characterization Prototype

![Verilog](https://img.shields.io/badge/Language-Verilog_HDL-blue.svg)
![C/C++](https://img.shields.io/badge/Language-C%2FC%2B%2B-green.svg)
![Platform](https://img.shields.io/badge/Platform-Altera_Cyclone_IV_%7C_STM32_Cortex--M-orange.svg)
![Status](https://img.shields.io/badge/Status-Functional_Prototype-brightgreen.svg)

## 📌 Project Overview
This repository contains the design and implementation of a heterogeneous co-processing system combining an **Altera Cyclone IV FPGA** and an **ARM Cortex-M Microcontroller**. Together, they form a highly integrated **Vector Network Analyzer (VNA) and Automated Filter Characterization System Prototype**. 

The system utilizes a Hardware-Software Co-design approach: the FPGA acts as the deterministic hardware accelerator for high-speed digital signal processing (DSP) and raw data acquisition, while the STM32 coordinates the runtime state machine, handles human-machine interfaces (HMI), and executes software-level calibration to linearize analog front-end (AFE) frequency responses.

---

## ⚙️ Key Technical Highlights & Architecture

### 1. FPGA Gateware Core (High-Speed Data Plane)
* **Coherent Sweeping & IQ Demodulation:** Implements synchronous digital down-conversion. Extracts weak signals by performing coherent averaging over 64 cycles after a dedicated stabilization period at each frequency step, significantly improving the SNR.
* **LUT-based DSP Accelerator Prototype:** Explores a trade-off architecture (`coord_transform.v`) that sacrifices block RAM resources for low latency. Uses ROM lookup tables (`.mif` initialized) to compute magnitudes ($\sqrt{I^2+Q^2}$) and features a hardware-level 4-quadrant `atan2` logic for precise phase extraction.
* **Hardware Filter Classifier:** Features a hardware heuristic state machine (`filter_analyzer.v`) that analyzes magnitude roll-offs across frequency sweeps to automatically classify unknown filters (LPF, HPF, BPF, BRF).
* **High-Robustness UART Link:** Implements a custom UART receiver (`uart_rx.v`) backed by **16x oversampling clock-ticks** with center-aligned sampling, ensuring zero-error asynchronous communication with the STM32.

### 2. STM32 Firmware Core (Control Plane & Calibration)
* **Layered Software Framework:** Decouples core logic into Application State Machine (`app.c`), Board Support Packages (`bsp_fpga_control.c`, `bsp_hmi.c`), and DMA-backed peripheral drivers, promoting firmware maintainability.
* **AFE Non-linear Linearization (Pre-distortion):** Develops a custom lookup table combined with a real-time linear interpolation engine (`lut_cal.c`). It mathematically offsets and compensates for the high-frequency attenuation caused by the Analog Front End across the 100Hz to 6000Hz spectrum, ensuring flat stimulus amplitude.
* **Asynchronous Packet Framing:** Drives the FPGA using dense 47-byte binary frames while concurrently processing asynchronous ASCII commands from the HMI screen via **UART IDLE Interrupts + DMA double-buffering**, achieving non-blocking data parsing.

---

## 🚧 Known Limitations & Optimization Roadmap
As an undergraduate prototype, the system successfully validates the heterogeneous architecture, but the RTL data-path currently has room for synthesizability and timing optimizations. My future work includes:
1. **True Hardware Pipelining:** Replacing behavioral simulation constructs (e.g., `$past` used for delay matching) with explicit shift-register chains to ensure strict RTL synthesizability and higher $F_{max}$.
2. **IP Core Integration:** Replacing the behavioral division placeholder in the DSP path with a pipelined `LPM_DIVIDE` vendor IP.
3. **Small-Signal Precision:** Introducing a Leading Zero Detector (LZD) prior to LUT addressing to implement dynamic block-floating-point scaling, addressing the truncation quantization noise for small inputs.

---

## 📂 Repository Structure
```text
├── FPGA_Gateware/               # FPGA Logic Design (Quartus II)
│   ├── src/                     # RTL Verilog Source Code
│   │   ├── top.v                # Top-Level Integration & FSM
│   │   ├── filter_analyzer.v    # Filter Classification Engine
│   │   ├── coord_transform.v    # LUT-based Coordinate Converter Prototype
│   │   ├── triangle_wave_generator.v # Phase-Accumulator based Generator
│   │   ├── command_parser.v     # 47-byte Custom Packet Bus Flattener
│   │   └── uart_rx.v / uart_tx.v# 16x Oversampling UART Transceivers
│   ├── constraints/             
│   │   └── tim.sdc              # Synopsis Design Constraints
│   └── sim/                     # MATLAB & Verilog Simulation Models
│
└── STM32_Firmware/              # Microcontroller Source Code
    ├── Core/Src/                # STM32 HAL & Low-level Drivers (DMA, UART)
    └── Core/software/           # Application Logic
        ├── app.c                # 5-Stage Central Core FSM
        ├── lut_cal.c            # Software Analog Gain Compensation (Interpolation)
        ├── bsp_fpga_control.c   # Float-to-Fixed Point Conversion & Framing
        └── bsp_hmi.c            # HMI Serial Communication Parser
