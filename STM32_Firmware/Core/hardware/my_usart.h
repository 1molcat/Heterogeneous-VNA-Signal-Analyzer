#ifndef __MY_USART_H__
#define __MY_USART_H__

#include "main.h" // 包含此文件以获取HAL库定义, 如 UART_HandleTypeDef 和 uint_t 类型

// ===================================================================================
// ===                       1. 公共函数原型声明                                   ===
// ===================================================================================
// 这些是 main.c 需要调用的函数

/**
 * @brief  初始化UART模块，主要是启动对PC的串口中断接收
 */
void UART_Init(void);

/**
 * @brief  检查是否有来自PC的新文本指令
 * @retval 1: 有新指令, 0: 没有新指令
 */
uint8_t Is_PC_Command_Ready(void);

/**
 * @brief  获取已接收到的PC指令字符串
 * @param  buffer: 一个足够大的字符数组指针，用于存储指令字符串
 */
void Get_PC_Command(char* buffer);

/**
 * @brief  解析来自PC的文本指令, 计算参数, 并将其转发给FPGA
 * @param  command_string: 指向接收到的、以'\0'结尾的字符串的指针
 */
void Process_PC_Command(char* command_string);


// ===================================================================================
// ===              2. 内部使用的函数原型 (可选，放在这里更清晰)                 ===
// ===================================================================================
// 虽然这些函数也在.c文件中，但将它们放在这里可以让您在main.c中也能调用它们进行计算

/**
 * @brief  计算FPGA所需的16位频率字
 * @param  target_freq_hz: 目标频率，单位 Hz
 * @retval 16位频率字
 */
uint16_t calculate_freq_word(float target_freq_hz);

/**
 * @brief  将波形参数打包并通过USART1发送给FPGA
 * @param  channel:   目标DAC通道 (1 或 2)
 * @param  wave_type: 波形类型 (0x00=Sine, 0x01=Triangle)
 * @param  frequency_word: 16位频率字
 * @param  phase_word: 16位相位字
 */
void Send_Waveform_Command_To_FPGA(uint8_t channel, uint8_t wave_type, uint32_t frequency_word_32, uint16_t phase_word_16, uint16_t amplitude_word_16);


#endif /* __MY_USART_H__ */ // <-- 最好让这里的名字和 #ifndef 的名字匹配
