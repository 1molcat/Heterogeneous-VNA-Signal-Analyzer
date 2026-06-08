#include "my_usart.h"
#include <stdio.h>
#include <stdlib.h>     // 用于 atof(), atoi()
#include <string.h>     // 用于 strtok(), strlen(), strcpy()
#include <ctype.h>      // 用于 toupper()
#include <math.h>       // 用于 pow(), round()
#include <stdint.h>     // 用于 uint8_t, uint16_t, uint32_t 等标准类型

// --- 外部变量声明 ---
// 假设 huart1 连接 FPGA, huart2 连接 PC
extern UART_HandleTypeDef huart1;
extern UART_HandleTypeDef huart2;

// --- 模块私有定义 ---
#define RX_BUFFER_SIZE         1          // UART中断每次只接收一个字节
#define PC_CMD_BUFFER_SIZE     150        // (MODIFIED) 存储来自PC的超长指令，例如 "1,1M,100,0,0,0,33,0,..."
#define FPGA_FRAME_SIZE        47         // (MODIFIED) 新协议的帧长度为47字节
#define NUM_HARMONICS          10         // 定义谐波数量
#define FPGA_SYS_CLK           50000000.0 // FPGA的系统时钟频率
#define FREQ_CALC_CONSTANT (4294967296.0 / 50000000.0)
// (MODIFIED) 新的结构体，用于存储谐波合成器的所有参数
typedef struct {
    uint8_t  channel;
    float    base_frequency;
    char     freq_unit;
    float    amplitudes[NUM_HARMONICS]; // 存储10个幅值百分比 (0-100)
    float    phases[NUM_HARMONICS];     // 存储10个相位 (0-360)
} HarmonicCommand_t;

// --- 模块私有变量 ---
static uint8_t rx_buffer[RX_BUFFER_SIZE];
static char    pc_cmd_buffer[PC_CMD_BUFFER_SIZE];
static volatile uint16_t pc_cmd_idx = 0; // (MODIFIED) 使用16位索引以防万一
static volatile uint8_t pc_cmd_received_flag = 0;

// --- 函数声明 ---
void Send_Harmonic_Command_To_FPGA(HarmonicCommand_t* cmd);
uint32_t calculate_freq_word_32(double target_freq_hz);
uint16_t calculate_phase_word_16(float target_phase_deg);
uint16_t calculate_amplitude_word_16(float target_amplitude_percent);

// ===================================================================================
// ===                       1. 公共接口函数 (给main.c调用)                        ===
// ===================================================================================
// 这部分代码无需修改

void UART_Init(void)
{
    HAL_UART_Receive_IT(&huart2, rx_buffer, RX_BUFFER_SIZE);
}

uint8_t Is_PC_Command_Ready(void)
{
    if (pc_cmd_received_flag) {
        pc_cmd_received_flag = 0;
        return 1;
    }
    return 0;
}

void Get_PC_Command(char* buffer)
{
    // 拷贝全局缓冲区的指令到外部提供的buffer中
    strcpy(buffer, pc_cmd_buffer);
    
    // *** 关键修复：取走数据后，立刻清空全局缓冲区 ***
    memset(pc_cmd_buffer, 0, sizeof(pc_cmd_buffer));
}

// ===================================================================================
// ===                     2. 核心逻辑函数 (处理和发送)                          ===
// ===================================================================================

/**
 * @brief  计算FPGA所需的【32位】频率字 (无需修改)
 */
uint32_t calculate_freq_word_32(double target_freq_hz)
{
    double freq_word_full = target_freq_hz * FREQ_CALC_CONSTANT;
    return (uint32_t)(round(freq_word_full));
}

/**
 * @brief  计算FPGA所需的【16位】相位字 (无需修改)
 */
uint16_t calculate_phase_word_16(float target_phase_deg)
{
    if (target_phase_deg > 360.0f) target_phase_deg = 360.0f;
    if (target_phase_deg < 0.0f)   target_phase_deg = 0.0f;
    return (uint16_t)(round((target_phase_deg / 360.0) * 65536.0));
}

/**
 * @brief  计算FPGA所需的【16位】幅值字 (无需修改)
 */
uint16_t calculate_amplitude_word_16(float target_amplitude_percent)
{
    if (target_amplitude_percent > 100.0f) target_amplitude_percent = 100.0f;
    if (target_amplitude_percent < 0.0f)   target_amplitude_percent = 0.0f;
    return (uint16_t)(round((target_amplitude_percent / 100.0) * 65535.0));
}


/**
 * @brief  (NEW) 向FPGA发送谐波合成指令 (遵循新的47字节协议)
 * @param  cmd: 指向一个包含所有已计算好的参数的结构体指针
 */
void Send_Harmonic_Command_To_FPGA(HarmonicCommand_t* cmd)
{
 uint8_t fpga_frame[FPGA_FRAME_SIZE];
    int i;

    // --- (MODIFIED) 使用 double 类型进行频率计算以保证精度 ---
    double final_frequency_hz = cmd->base_frequency;
    if (cmd->freq_unit == 'K') final_frequency_hz *= 1000.0;
    else if (cmd->freq_unit == 'M') final_frequency_hz *= 1000000.0;
    uint32_t freq_word_32 = calculate_freq_word_32(final_frequency_hz);
    uint16_t amp_words[NUM_HARMONICS];
    uint16_t phase_words[NUM_HARMONICS];

    for (i = 0; i < NUM_HARMONICS; ++i) {
        amp_words[i] = calculate_amplitude_word_16(cmd->amplitudes[i]);
        phase_words[i] = calculate_phase_word_16(cmd->phases[i]);
    }

    // --- 开始打包47字节的帧 ---
    fpga_frame[0] = 0xA5;         // Byte 0: 帧头
    fpga_frame[1] = cmd->channel; // Byte 1: 通道

    // --- 打包32位基频字 (Little Endian) ---
    fpga_frame[2] = (uint8_t)(freq_word_32 & 0xFF);
    fpga_frame[3] = (uint8_t)((freq_word_32 >> 8) & 0xFF);
    fpga_frame[4] = (uint8_t)((freq_word_32 >> 16) & 0xFF);
    fpga_frame[5] = (uint8_t)((freq_word_32 >> 24) & 0xFF);

    // --- 循环打包10组幅度和相位 ---
    for (i = 0; i < NUM_HARMONICS; ++i) {
        int base_index = 6 + i * 4; // 每个谐波数据占4字节
        
        // 打包16位幅值 (Little Endian)
        fpga_frame[base_index + 0] = (uint8_t)(amp_words[i] & 0xFF);
        fpga_frame[base_index + 1] = (uint8_t)((amp_words[i] >> 8) & 0xFF);
        
        // 打包16位相位 (Little Endian)
        fpga_frame[base_index + 2] = (uint8_t)(phase_words[i] & 0xFF);
        fpga_frame[base_index + 3] = (uint8_t)((phase_words[i] >> 8) & 0xFF);
    }
    
    fpga_frame[46] = 0x5A; // Byte 46: 帧尾

    // 通过 huart1 发送47字节给 FPGA
    HAL_UART_Transmit(&huart1, fpga_frame, FPGA_FRAME_SIZE, 200);
}


/**
 * @brief  (MODIFIED) 解析来自PC的谐波合成指令
 * @param  command_string: 指向接收到的、以'\0'结尾的字符串的指针
 *         例如: "1,1M,100,0,0,0,33.3,0,0,0,20,0,14.2,0,11.1,0,9.1,0,7.7,0,6.7,0"
 *         格式: CH, F, A1, P1, A2, P2, ... , A10, P10  (共22个参数)
 */
void Process_PC_Command(char* command_string)
{
    HarmonicCommand_t parsed_cmd = {0}; // 初始化结构体
    char* token;
    int i;

    // --- 解析第1部分：通道 ---
    token = strtok(command_string, ",");
    if (token == NULL) return;
    parsed_cmd.channel = (uint8_t)atoi(token);
    if (parsed_cmd.channel != 1 && parsed_cmd.channel != 2) return;

    // --- 解析第2部分：基频 ---
    token = strtok(NULL, ",");
    if (token == NULL) return;
    parsed_cmd.base_frequency = atof(token);
    int len = strlen(token);
    if (len > 0) parsed_cmd.freq_unit = toupper(token[len-1]);

    // --- 循环解析10组幅度和相位 ---
    for (i = 0; i < NUM_HARMONICS; ++i) {
        // 解析幅度 A_i
        token = strtok(NULL, ",");
        if (token == NULL) {
            // 如果指令不完整，则将剩余参数设为0
            parsed_cmd.amplitudes[i] = 0.0f;
            parsed_cmd.phases[i] = 0.0f;
            continue;
        }
        parsed_cmd.amplitudes[i] = atof(token);
        
        // 解析相位 P_i
        token = strtok(NULL, ",");
        if (token == NULL) {
            // 如果指令不完整，相位设为0
            parsed_cmd.phases[i] = 0.0f;
            continue;
        }
        parsed_cmd.phases[i] = atof(token);
    }

    // --- 调用发送函数，将解析并计算好的数据打包发送给FPGA ---
    Send_Harmonic_Command_To_FPGA(&parsed_cmd);
}

// ===================================================================================
// ===                       3. 中断处理 (HAL库回调)                               ===
// ===================================================================================
// 修改了索引变量类型
void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
    if (huart->Instance == USART2) 
    {
        uint8_t received_byte = rx_buffer[0];

        if (received_byte == '\n' || received_byte == '\r') 
        {
            if (pc_cmd_idx > 0)
            {
                pc_cmd_buffer[pc_cmd_idx] = '\0';
                pc_cmd_received_flag = 1;
                pc_cmd_idx = 0;
            }
        }
        else if (pc_cmd_idx < PC_CMD_BUFFER_SIZE - 1)
        {
            pc_cmd_buffer[pc_cmd_idx++] = received_byte;
        }
        
        HAL_UART_Receive_IT(&huart2, rx_buffer, 1);
    }
}
