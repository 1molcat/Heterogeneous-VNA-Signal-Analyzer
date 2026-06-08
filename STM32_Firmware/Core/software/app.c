// --- START OF FILE app.c (最终完整版 - 循环解析 - 全英文) ---

#include "app.h"
#include "bsp_fpga_control.h"
#include "bsp_hmi.h"
#include "lut_cal.h"
#include <stdio.h>

// --- Definitions ---
#define FREQ_WORD_TO_HZ (50000000.0 / 4294967296.0)

// --- FPGA返回的数据包格式定义 ---
#define VNA_PACKET_HEADER 0xA5
#define VNA_PACKET_FOOTER 0x5A
#define VNA_PACKET_LENGTH 10

#define TYPE_PACKET_HEADER 0xB5
#define TYPE_PACKET_FOOTER 0x5B
#define TYPE_PACKET_LENGTH 3


// --- Private Variables ---
static App_State_t g_app_state = APP_MODE_IDLE;
static float g_mode1_freq_hz = 1000.0f;
static float g_mode1_amp_vpp = 1.0f; 
static float g_mode3_freq_hz = 100.0f; // Mode 3 初始频率
static float g_mode3_target_vout_vpp = 1.0f; // Mode 3 初始目标输出电压
static float g_mode4_amp_vpp = 1.0f;

// --- Private Function Declarations ---
static void update_fpga_output(void);
static void handle_hmi_command(HMI_Command_t cmd);

// --- Public Functions ---

void App_Init(void) {
    FPGA_Init();
    HMI_Init();
    
    g_app_state = APP_MODE_IDLE;
    FPGA_Output_Disable();
    HMI_Printf("page 0"); // 假设 page 0 是主菜单页面
}

void App_Loop(void) {
    // Event-driven, so main loop can be empty.
}

void App_HMI_RxCallback(uint8_t *buffer, uint16_t len) {
    HMI_Command_t cmd = HMI_Parse_Command(buffer, len);
    handle_hmi_command(cmd);
}

void App_FPGA_Data_RxCallback(uint8_t *buffer, uint16_t len) {
    char hmi_buf[64];

    // 1. 定义我们正在寻找的数据包的特征
    const uint8_t  PACKET_HEADER = 0xB5;
    const uint8_t  PACKET_FOOTER = 0x5B;
    const uint16_t PACKET_LENGTH = 3;

    // 2. 遍历接收到的所有数据，寻找包头
    //    修复：循环条件改为 (i < len - PACKET_LENGTH + 1) 或者 (i <= len - PACKET_LENGTH)
    for (uint16_t i = 0; i <= len - PACKET_LENGTH; ++i) {
        
        // 3. 判断当前字节是否是包头，并且后续字节是否是包尾
        if (buffer[i] == PACKET_HEADER && buffer[i + PACKET_LENGTH - 1] == PACKET_FOOTER) {
            
            // --- 找到了一个完整的包！ ---
            
            // 提取中间的类型代码
            uint8_t filter_type_code = buffer[i + 1]; // 在 B5 01 5B 中，这就是 01
            const char* filter_name = "Unknown";

            // 根据类型代码转换为字符串
            switch (filter_type_code) {
                case 0x01: filter_name = "LPF"; break;
                case 0x02: filter_name = "HPF"; break;
                case 0x03: filter_name = "BPF"; break;
                case 0x04: filter_name = "BRF"; break;
                default:   filter_name = "Failed"; break;
            }

            // --- 向HMI发送指令，更新UI ---
            
            // a. 更新文本框 t1 的内容为识别出的滤波器类型
            sprintf(hmi_buf, "t1.txt=\"%s\"", filter_name);
            HMI_Printf(hmi_buf);
            
            // b. 隐藏 "Learning..." 文本 (控件 t2)
            HMI_Printf("vis t2,0");

            // --- 任务完成，立即返回 ---
            // 因为我们已经找到了需要的信息，所以直接退出函数，
            // 不再继续解析后面的 "A5 ..." 无效数据。
            return; 
        }
    }
    
    // 如果整个 for 循环都跑完了还没找到，说明这次收到的数据里没有我们想要的包。
    // 这种情况就什么都不做。
}


// --- Private Functions ---

static void update_fpga_output(void) {
    char hmi_buf[64];

    switch (g_app_state) {
        case APP_MODE_1_FREQ_SWEEP:
            FPGA_Set_Single_SineWave(g_mode1_freq_hz, g_mode1_amp_vpp, 0);
            sprintf(hmi_buf, "t2.txt=\"%.0f\"", g_mode1_freq_hz); HMI_Printf(hmi_buf); 
            sprintf(hmi_buf, "t1.txt=\"%.2f\"", g_mode1_amp_vpp); HMI_Printf(hmi_buf); 
            break;

        case APP_MODE_2_FIXED_CAL:
            {
                float target_freq = 1000.0f;
                float target_vout = 2.0f;
                float required_input_vpp = LUT_GetRequiredInputVpp(target_freq, target_vout);
                if (required_input_vpp > 0) {
                    FPGA_Set_Single_SineWave(target_freq, required_input_vpp, 0);
                    sprintf(hmi_buf, "t4.txt=\"%.3f\"", required_input_vpp); HMI_Printf(hmi_buf); 
                } else {
                    FPGA_Output_Disable();
                    HMI_Printf("t4.txt=\"OOR!\"");
                }
            }
            break;

        case APP_MODE_3_CALIBRATED_SWEEP:
            {
                float required_input_vpp = LUT_GetRequiredInputVpp(g_mode3_freq_hz, g_mode3_target_vout_vpp);
                
                sprintf(hmi_buf, "t4.txt=\"%.2f\"", g_mode3_target_vout_vpp);
                HMI_Printf(hmi_buf);
                sprintf(hmi_buf, "t6.txt=\"%.0f\"", g_mode3_freq_hz);
                HMI_Printf(hmi_buf);

                if (required_input_vpp > 0) {
                    if (required_input_vpp > MAX_DAC_OUTPUT_VPP) {
                        FPGA_Output_Disable();
                        HMI_Printf("t6.txt=\"MAX!\"");
                    } else {
                        FPGA_Set_Single_SineWave(g_mode3_freq_hz, required_input_vpp, 0);
                    }
                } else {
                    FPGA_Output_Disable();
                    HMI_Printf("t6.txt=\"OOR!\"");
                }
            }
            break;

        case APP_MODE_4_VNA_SWEEP:
            // VNA扫描的启动由特定命令触发，此处不执行操作
            break;
            
        case APP_MODE_5_LEARN:
            FPGA_Output_Disable(); // 在学习模式下，禁用输出
            break;

        case APP_MODE_IDLE:
        default:
            FPGA_Output_Disable();
            break;
    }
}

static void handle_hmi_command(HMI_Command_t cmd) {
    if (cmd.event == HMI_CMD_NONE) return;

    if (g_app_state == APP_MODE_4_VNA_SWEEP && 
       (cmd.event >= HMI_CMD_SET_MODE_1 && cmd.event <= HMI_CMD_GOTO_LEARN_PAGE)) {
         FPGA_Stop_VNA_Sweep();
    }
    
    switch (cmd.event) {
        // --- 页面切换 ---
        case HMI_CMD_SET_MODE_1: g_app_state = APP_MODE_1_FREQ_SWEEP; HMI_Printf("page 1"); break;
        case HMI_CMD_SET_MODE_2: g_app_state = APP_MODE_2_FIXED_CAL;  HMI_Printf("page 2"); break;
        case HMI_CMD_SET_MODE_3: g_app_state = APP_MODE_3_CALIBRATED_SWEEP; HMI_Printf("page 3"); break;
        case HMI_CMD_SET_MODE_4: 
            {
                g_app_state = APP_MODE_4_VNA_SWEEP;
                char hmi_buf[64];
                HMI_Printf("page 4");
                HMI_Printf("freq4.txt=\"-- Hz\"");
                HMI_Printf("i_val.txt=\"I: --\"");
                HMI_Printf("q_val.txt=\"Set Vpp to Start\"");
                sprintf(hmi_buf, "amp4.txt=\"%.2f Vpp\"", g_mode4_amp_vpp);
                HMI_Printf(hmi_buf);
                FPGA_Output_Disable();
                return; 
            }
		
		case HMI_CMD_GOTO_LEARN_PAGE:
            g_app_state = APP_MODE_5_LEARN;
            HMI_Printf("page 4"); // 跳转到你的“扩展”页面
            // 初始化页面UI
            HMI_Printf("t1.txt=\"Unknown\"");
            HMI_Printf("vis t2,0"); // 确保"学习中..."初始隐藏
            update_fpga_output();
            return;

        case HMI_CMD_LEARN_START:
            if (g_app_state == APP_MODE_5_LEARN) {
                // 1. 更新UI
                HMI_Printf("t1.txt=\"Unknown\"");
                HMI_Printf("t2.txt=\"Learning...\"");
                HMI_Printf("vis t2,1");
                // 2. 向FPGA发送开始学习的指令
                FPGA_Start_Learning();
            }
            return;

        // --- 频率控制 (通用) ---
        case HMI_CMD_FREQ_INC:
            if (g_app_state == APP_MODE_1_FREQ_SWEEP) { g_mode1_freq_hz += 100.0f; if (g_mode1_freq_hz > 2000000.0f) g_mode1_freq_hz = 2000000.0f; } 
            else if (g_app_state == APP_MODE_3_CALIBRATED_SWEEP) { g_mode3_freq_hz += 100.0f; if (g_mode3_freq_hz > 6000.0f) g_mode3_freq_hz = 6000.0f; }
            break;

        case HMI_CMD_FREQ_DEC:
            if (g_app_state == APP_MODE_1_FREQ_SWEEP) { g_mode1_freq_hz -= 100.0f; if (g_mode1_freq_hz < 100.0f) g_mode1_freq_hz = 100.0f; } 
            else if (g_app_state == APP_MODE_3_CALIBRATED_SWEEP) { g_mode3_freq_hz -= 100.0f; if (g_mode3_freq_hz < 100.0f) g_mode3_freq_hz = 100.0f; }
            break;

        case HMI_CMD_FREQ_SET_MAX:
            if (g_app_state == APP_MODE_1_FREQ_SWEEP) { g_mode1_freq_hz = 1000000.0f; }
            break;

        // --- 幅度/目标电压控制 (通用) ---
        case HMI_CMD_AMP_INC:
            if (g_app_state == APP_MODE_1_FREQ_SWEEP) { g_mode1_amp_vpp += 0.1f; if (g_mode1_amp_vpp > MAX_DAC_OUTPUT_VPP) g_mode1_amp_vpp = MAX_DAC_OUTPUT_VPP; }
            else if (g_app_state == APP_MODE_3_CALIBRATED_SWEEP) { g_mode3_target_vout_vpp += 0.1f; if (g_mode3_target_vout_vpp > 5.0f) g_mode3_target_vout_vpp = 5.0f; }
            break;

        case HMI_CMD_AMP_DEC:
            if (g_app_state == APP_MODE_1_FREQ_SWEEP) { g_mode1_amp_vpp -= 0.1f; if (g_mode1_amp_vpp < 0.0f) g_mode1_amp_vpp = 0.0f; }
            else if (g_app_state == APP_MODE_3_CALIBRATED_SWEEP) { g_mode3_target_vout_vpp -= 0.1f; if (g_mode3_target_vout_vpp < 0.1f) g_mode3_target_vout_vpp = 0.1f; }
            break;

        case HMI_CMD_AMP_VPP_SET:
            if (g_app_state == APP_MODE_1_FREQ_SWEEP) { g_mode1_amp_vpp = cmd.value; if (g_mode1_amp_vpp > MAX_DAC_OUTPUT_VPP) g_mode1_amp_vpp = MAX_DAC_OUTPUT_VPP; if (g_mode1_amp_vpp < 0) g_mode1_amp_vpp = 0; }
            break;

        // --- VNA模式控制 ---
        case HMI_CMD_VNA_AMP_SET:
            if (g_app_state == APP_MODE_4_VNA_SWEEP) {
                g_mode4_amp_vpp = cmd.value;
                if (g_mode4_amp_vpp > MAX_DAC_OUTPUT_VPP) g_mode4_amp_vpp = MAX_DAC_OUTPUT_VPP;
                if (g_mode4_amp_vpp < 0) g_mode4_amp_vpp = 0;
                FPGA_Start_VNA_Sweep_With_Amp(g_mode4_amp_vpp);
                char hmi_buf[64];
                sprintf(hmi_buf, "amp4.txt=\"%.2f Vpp\"", g_mode4_amp_vpp);
                HMI_Printf(hmi_buf);
                HMI_Printf("i_val.txt=\"I: --\"");
                HMI_Printf("q_val.txt=\"Q: --\"");
                return;
            }
            break;
            
        default:
            return;
    }
    
    // 根据新的状态或参数，统一刷新FPGA/HMI
    update_fpga_output();
}
