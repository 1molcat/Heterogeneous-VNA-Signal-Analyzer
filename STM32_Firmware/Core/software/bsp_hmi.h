#ifndef BSP_HMI_H
#define BSP_HMI_H

#include "main.h"

// HMI命令事件类型
typedef enum {
    HMI_CMD_NONE = 0,
    HMI_CMD_SET_MODE_1,          // 切换到模式1 (基础二：波形产生)
    HMI_CMD_SET_MODE_2,          // 切换到模式2 (基础三：定值输出)
    HMI_CMD_SET_MODE_3,          // 切换到模式3 (发挥一：校准输出)
    HMI_CMD_SET_MODE_4,          // 切换到模式4 (发挥二：VNA扫描)
    HMI_CMD_GOTO_LEARN_PAGE,     // 切换到学习页面 (发挥部分)
    
    // Mode 1 (波形产生) 的指令
    HMI_CMD_FREQ_INC,            
    HMI_CMD_FREQ_DEC,            
    HMI_CMD_FREQ_SET_MAX,        
    HMI_CMD_AMP_INC,             
    HMI_CMD_AMP_DEC,             
    HMI_CMD_AMP_VPP_SET,         
    
    // 其他指令
    HMI_CMD_TARGET_VOUT_SET,     // (旧指令，可保留或删除)
    HMI_CMD_VNA_AMP_SET,         
    HMI_CMD_LEARN_START,         

    // --- START: 新增 Mode 3 (校准输出) 的专属指令 ---
    HMI_CMD_MODE3_VOUT_INC,      // 目标输出电压增加
    HMI_CMD_MODE3_VOUT_DEC,      // 目标输出电压减少
    HMI_CMD_MODE3_FREQ_INC,      // 目标频率增加
    HMI_CMD_MODE3_FREQ_DEC       // 目标频率减少
    // --- END: 新增 Mode 3 (校准输出) 的专属指令 ---

} HMI_Command_Event_t;

// HMI命令结构体
typedef struct {
    HMI_Command_Event_t event;
    float value;
} HMI_Command_t;

void HMI_Init(void);
void HMI_Printf(const char *format, ...);
HMI_Command_t HMI_Parse_Command(uint8_t *buffer, uint16_t len);

#endif // BSP_HMI_H