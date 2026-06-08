# Heterogeneous FPGA-ARM Vector Network Analyzer & Automated Filter Characterization System

![Verilog](https://img.shields.io/badge/Language-Verilog_HDL-blue.svg)
![C/C++](https://img.shields.io/badge/Language-C%2FC%2B%2B-green.svg)
![Platform](https://img.shields.io/badge/Platform-Altera_Cyclone_IV_%7C_STM32_Cortex--M-orange.svg)
![Status](https://img.shields.io/badge/Status-Validated_&_Tested-brightgreen.svg)

## 📌 Project Overview
This repository contains the complete design and implementation files for an industrial-grade, heterogeneous co-processing system combining an **Altera Cyclone IV FPGA** and an **ARM Cortex-M Microcontroller**. Together, they form a highly integrated **Vector Network Analyzer (VNA) and Automated Filter Characterization System**. 

The system leverages the deterministic hardware parallelism of the FPGA to execute high-speed digital signal processing (DSP) and sampling routines, while the ARM processor coordinates the runtime state machine, handles human-machine interfaces (HMI), and executes software-level calibration to linearize analog front-end (AFE) frequency responses.

---

## ⚙️ Key Technical Highlights & Architecture

### 1. FPGA Gateware Core (High-Speed DSP Pipeline)
* **Multiplier-less Coherent Demodulation:** Implements a highly optimized IQ demodulator using the phase accumulator's quadrant-overflow properties to perform synchronous sampling without draining hardware multipliers, ensuring zero phase-lag and low resource usage.
* **8-Stage Pipelined Coordinate Transformation:** Features a fully pipelined Rectangular-to-Polar converter (`coord_transform.v`) backed by combinational LUTs, resolving full 4-quadrant `atan2` phase corrections natively in hardware.
* **Deterministic Boundary-Based Filter Analyzer:** Embedded with a hardware heuristic state machine (`filter_analyzer.v`) that analyzes real-time DC vs. HF magnitude roll-offs to instantly classify unknown filters (LPF, HPF, BPF, BRF) and transmits results via deterministic frame bursts.
* **Hand-Coded Phase Accumulators:** Features a resource-efficient Triangle Wave Engine built via phase folding bit-manipulation running close to the raw silicone $F_{max}$.
* **Glitch-Resilient Communication:** Implements a custom UART receiver backed by **16x oversampling clock-ticks** and 3-stage cross-clock domain (CDC) sync registers to reject industrial environment electromagnetic interference.

### 2. STM32 Firmware Core (Layered Architecture & Calibration)
* **Layered Software Framework:** Decouples core logic beautifully into Application (`app.c`), Board Support Packages (`bsp_fpga_control.c`, `bsp_hmi.c`), and low-level peripheral drivers (`my_usart.c`) to promote industrial maintainability.
* **AFE Non-linear Linearization Algorithm:** Employs a custom lookup table combined with a real-time linear interpolation engine (`lut_cal.c`) to mathematically offset and compensate for high-frequency attenuation caused by the Analog Front End across 100Hz to 6000Hz.
* **Robust Packet Framing:** Drives the FPGA using 47-byte strict binary frames while processing asynchronous ASCII command streams from the user control screen concurrently using efficient tokenization and data type conversions.

---

## 📂 Repository Structure
```text
├── FPGA_Gateware/               # FPGA Logic Design (Quartus II)
│   ├── usart2FPGA.qpf           # Quartus Project File
│   ├── usart2FPGA.qsf           # Project Settings and Pin Assignments
│   ├── src/                     # RTL Verilog Source Code
│   │   ├── top.v                # Top-Level Infrastructure & DSP Multistage Pipeline
│   │   ├── filter_analyzer.v    # Filter Classification FSM Engine
│   │   ├── coord_transform.v    # 8-Stage CORDIC-less Coordinate Converter
│   │   ├── triangle_wave_generator.v # High-Speed Phase-Folding Triangle Generator
│   │   ├── command_parser.v     # 12-byte Custom Packet Bus Flattener
│   │   └── uart_rx.v / uart_tx.v# 16x Oversampling Robust UART Transceivers
│   ├── constraints/             
│   │   └── tim.sdc              # Synopsis Design Constraints (50MHz Clock Driving)
│   └── sim/                     
│       └── tb_top.v             # Automated UART Instruction Packet Injector Testbench
│
└── STM32_Firmware/              # Microcontroller Source Code (Keil MDK)
    ├── usart2FPGA.uvprojx       # Keil uVision Project File
    ├── usart2FPGA.ioc           # STM32CubeMX Initialization Configuration
    ├── App/                     # Application State Machine & DSP Calibration
    │   ├── app.c                # Central Core FSM Handler
    │   └── lut_cal.c            # Software Analog Gain Compensation Lookup & Interpolation
    ├── BSP/                     # Board Support Packages (Hardware Abstraction Layers)
    │   ├── bsp_fpga_control.c   # 47-byte Command Packaging & Transmission Interface
    │   └── bsp_hmi.c            # Touch Screen Interface Serial Communication Driver
    └── Drivers/                 
        └── my_usart.c           # Interrupt-driven String Parsing & Frame Isolation
