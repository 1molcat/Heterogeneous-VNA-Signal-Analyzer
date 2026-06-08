#ifndef APP_H
#define APP_H

#include "main.h"
#include "bsp_hmi.h" // 包含 HMI 头文件以使用其定义


// 定义所有应用模式的枚举
typedef enum {
    APP_MODE_IDLE,
    APP_MODE_1_FREQ_SWEEP,      // 基础二：波形产生
    APP_MODE_2_FIXED_CAL,       // 基础三：定值输出
    APP_MODE_3_CALIBRATED_SWEEP,// 发挥一：校准输出
    APP_MODE_4_VNA_SWEEP,       // 发挥二：VNA扫描
    APP_MODE_5_LEARN            // 新增: 发挥部分 - 学习模式
} App_State_t;

// --- Public Function Prototypes ---

// App 初始化
void App_Init(void);

// App 主循环 (事件驱动，可能为空)
void App_Loop(void);

// HMI 数据接收回调函数 (在usart.c的接收中断回调中调用)
void App_HMI_RxCallback(uint8_t *buffer, uint16_t len);

// FPGA 数据接收回调函数 (在usart.c的接收中断回调中调用)
void App_FPGA_Data_RxCallback(uint8_t *buffer, uint16_t len);



#endif // APP_H