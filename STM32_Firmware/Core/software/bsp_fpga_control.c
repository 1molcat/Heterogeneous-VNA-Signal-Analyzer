// --- START OF FILE bsp_fpga_control.c ---
// (最终修正版)

#include "bsp_fpga_control.h"
#include <math.h>
#include <string.h>

// --- Constants ---
#define FPGA_FRAME_SIZE        47
#define FPGA_SYS_CLK           50000000.0
#define FREQ_CALC_CONSTANT     (4294967296.0 / 50000000.0)

// --- External Variables ---
extern UART_HandleTypeDef huart1;

// --- Private Calculation Functions (Helper functions) ---

// (这三个 calculation 函数保持不变)
static uint32_t calculate_freq_word_32(double target_freq_hz) {
    return (uint32_t)round(target_freq_hz * FREQ_CALC_CONSTANT);
}
static uint16_t calculate_phase_word_16(float target_phase_deg) {
    target_phase_deg = fmodf(target_phase_deg, 360.0f);
    if (target_phase_deg < 0) {
        target_phase_deg += 360.0f;
    }
    return (uint16_t)roundf((target_phase_deg / 360.0f) * 65536.0f);
}
static uint16_t calculate_amplitude_word_16(float amplitude_vpp) {
    if (amplitude_vpp > MAX_DAC_OUTPUT_VPP) amplitude_vpp = MAX_DAC_OUTPUT_VPP;
    if (amplitude_vpp < 0.0f)               amplitude_vpp = 0.0f;
    
    float percent = (amplitude_vpp / MAX_DAC_OUTPUT_VPP) * 100.0f;
    return (uint16_t)roundf((percent / 100.0f) * 65535.0f);
}

// (send_fpga_simple_command 函数保持不变)
static void send_fpga_simple_command(uint8_t command_id) {
    uint8_t fpga_frame[FPGA_FRAME_SIZE];
    memset(fpga_frame, 0, FPGA_FRAME_SIZE);
    fpga_frame[0] = 0xA5;
    fpga_frame[1] = command_id;
    fpga_frame[FPGA_FRAME_SIZE - 1] = 0x5A;
    HAL_UART_Transmit(&huart1, fpga_frame, FPGA_FRAME_SIZE, 200);
}

// --- Public Function Implementations ---

void FPGA_Init(void) {
    // 由 main 函数中的 HAL_UART_Init 完成
}

void FPGA_Output_Disable(void) {
    send_fpga_simple_command(0x03); 
}

// (FPGA_Set_Single_SineWave 函数保持不变)
void FPGA_Set_Single_SineWave(float freq_hz, float amplitude_vpp, float phase_deg) {
    uint8_t fpga_frame[FPGA_FRAME_SIZE];
    memset(fpga_frame, 0, FPGA_FRAME_SIZE);
    uint32_t freq_word = calculate_freq_word_32(freq_hz);
    uint16_t amp_word = calculate_amplitude_word_16(amplitude_vpp);
    uint16_t phase_word = calculate_phase_word_16(phase_deg);
    fpga_frame[0] = 0xA5; fpga_frame[1] = 2;
    fpga_frame[2] = (uint8_t)(freq_word);
    fpga_frame[3] = (uint8_t)(freq_word >> 8);
    fpga_frame[4] = (uint8_t)(freq_word >> 16);
    fpga_frame[5] = (uint8_t)(freq_word >> 24);
    int base_index = 6;
    fpga_frame[base_index + 0] = (uint8_t)(amp_word);
    fpga_frame[base_index + 1] = (uint8_t)(amp_word >> 8);
    fpga_frame[base_index + 2] = (uint8_t)(phase_word);
    fpga_frame[base_index + 3] = (uint8_t)(phase_word >> 8);
    fpga_frame[FPGA_FRAME_SIZE - 1] = 0x5A;
    HAL_UART_Transmit(&huart1, fpga_frame, FPGA_FRAME_SIZE, 200);
}

// (FPGA_Start_VNA_Sweep_With_Amp 函数保持不变)
void FPGA_Start_VNA_Sweep_With_Amp(float amp_vpp) {
    uint8_t fpga_frame[FPGA_FRAME_SIZE] = {0};
    uint16_t amp_word = calculate_amplitude_word_16(amp_vpp);
    fpga_frame[0] = 0xA5; 
    fpga_frame[1] = 0x05;
    fpga_frame[2] = (uint8_t)(amp_word);
    fpga_frame[3] = (uint8_t)(amp_word >> 8);
    fpga_frame[FPGA_FRAME_SIZE - 1] = 0x5A;
    HAL_UART_Transmit(&huart1, fpga_frame, FPGA_FRAME_SIZE, 200);
}

void FPGA_Start_VNA_Sweep(void) {
    FPGA_Start_VNA_Sweep_With_Amp(1.0f);
}

void FPGA_Stop_VNA_Sweep(void) {
    send_fpga_simple_command(0x04);
}

/**
 * @brief 命令FPGA开始自主学习未知滤波器
 * @note  根据FPGA设计，此操作使用ID=6的指令，并需要提供一个激励幅度。
 */
void FPGA_Start_Learning(void) {
    uint8_t fpga_frame[FPGA_FRAME_SIZE];
    memset(fpga_frame, 0, FPGA_FRAME_SIZE);

    // 默认使用1.0 Vpp的激励电压进行学习
    float amplitude_vpp = 1.0f;
    uint16_t amp_word = calculate_amplitude_word_16(amplitude_vpp);

    // --- 组装命令帧 ---
    fpga_frame[0] = 0xA5;       // 帧头
    fpga_frame[1] = 6;          // 命令ID 6: 开始学习
    
    // 根据FPGA设计，学习指令也需要幅度参数
    // 我们使其与VNA扫描的幅度参数位置和字节序保持一致
    // (小端模式: 低字节在前，高字节在后)
    fpga_frame[2] = (uint8_t)(amp_word);        // 低字节
    fpga_frame[3] = (uint8_t)(amp_word >> 8);    // 高字节
    
    fpga_frame[FPGA_FRAME_SIZE - 1] = 0x5A; // 帧尾
    
    HAL_UART_Transmit(&huart1, fpga_frame, FPGA_FRAME_SIZE, 200);
}
