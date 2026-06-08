// --- START OF FILE bsp_hmi.c ---
#include "bsp_hmi.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>

extern UART_HandleTypeDef huart2; 
#define HMI_UART_HANDLE huart2

void HMI_Init(void) {
    // Initialization is handled by HAL drivers.
}

void HMI_Printf(const char *format, ...) {
    char buffer[128];
    va_list args;
    va_start(args, format);
    int len = vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);

    if (len > 0 && len < sizeof(buffer)) {
       HAL_UART_Transmit(&HMI_UART_HANDLE, (uint8_t*)buffer, len, 100);
       const uint8_t end_frame[3] = {0xFF, 0xFF, 0xFF};
       HAL_UART_Transmit(&HMI_UART_HANDLE, end_frame, 3, 100);
    }
}

HMI_Command_t HMI_Parse_Command(uint8_t *buffer, uint16_t len) {
    HMI_Command_t cmd = { .event = HMI_CMD_NONE, .value = 0.0f };
    char* str_buf = (char*)buffer;

    if (len < 128) { str_buf[len] = '\0'; } else { str_buf[127] = '\0'; }

    // --- 命令解析 ---
    if (strncmp(str_buf, "mode 1", 6) == 0) { cmd.event = HMI_CMD_SET_MODE_1; } 
    else if (strncmp(str_buf, "mode 2", 6) == 0) { cmd.event = HMI_CMD_SET_MODE_2; } 
    else if (strncmp(str_buf, "mode 3", 6) == 0) { cmd.event = HMI_CMD_SET_MODE_3; } 
    else if (strncmp(str_buf, "mode 4", 6) == 0) { cmd.event = HMI_CMD_SET_MODE_4; } 
    else if (strncmp(str_buf, "mode 5", 6) == 0) { cmd.event = HMI_CMD_GOTO_LEARN_PAGE; } 
    else if (strncmp(str_buf, "learn_start", 11) == 0) { cmd.event = HMI_CMD_LEARN_START; } 
    else if (strncmp(str_buf, "freq_inc", 8) == 0) { cmd.event = HMI_CMD_FREQ_INC; } 
    else if (strncmp(str_buf, "freq_dec", 8) == 0) { cmd.event = HMI_CMD_FREQ_DEC; } 
    else if (strncmp(str_buf, "freq_max", 8) == 0) { cmd.event = HMI_CMD_FREQ_SET_MAX; } 
    else if (strncmp(str_buf, "amp_inc", 7) == 0) { cmd.event = HMI_CMD_AMP_INC; } 
    else if (strncmp(str_buf, "amp_dec", 7) == 0) { cmd.event = HMI_CMD_AMP_DEC; } 
    else if (strncmp(str_buf, "set_amp ", 8) == 0) { cmd.event = HMI_CMD_AMP_VPP_SET; cmd.value = atof(str_buf + 8); } 
    else if (strncmp(str_buf, "set_vout ", 9) == 0) { cmd.event = HMI_CMD_TARGET_VOUT_SET; cmd.value = atof(str_buf + 9); } 
    else if (strncmp(str_buf, "set_vna_amp ", 12) == 0) { cmd.event = HMI_CMD_VNA_AMP_SET; cmd.value = atof(str_buf + 12); }
    
    // --- START: 解析新的 Mode 3 指令 ---
    // 假设HMI按钮发送的指令是 "m3_vout_inc", "m3_freq_inc" 等
    else if (strncmp(str_buf, "m3_vout_inc", 11) == 0) { cmd.event = HMI_CMD_MODE3_VOUT_INC; }
    else if (strncmp(str_buf, "m3_vout_dec", 11) == 0) { cmd.event = HMI_CMD_MODE3_VOUT_DEC; }
    else if (strncmp(str_buf, "m3_freq_inc", 11) == 0) { cmd.event = HMI_CMD_MODE3_FREQ_INC; }
    else if (strncmp(str_buf, "m3_freq_dec", 11) == 0) { cmd.event = HMI_CMD_MODE3_FREQ_DEC; }
    // --- END: 解析新的 Mode 3 指令 ---
    
    return cmd;
}
// --- END OF FILE bsp_hmi.c ---