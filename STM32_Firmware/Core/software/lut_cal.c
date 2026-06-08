#include "lut_cal.h"
#include <stddef.h> // for NULL

// 定义查找表的数据点结构
typedef struct {
    float freq_hz;
    float vpp_gain; // 电压增益 (Vpp_out / Vpp_in), 根据您的数据，此值等于 "实际输出_Vpp"
} Lut_Point_t;

// --- 增益查找表 (已使用您提供的 100Hz - 6000Hz 的完整数据更新) ---
static const Lut_Point_t g_gain_lut[] = {
    {100.0f, 5.12f},    {200.0f, 4.96f},    {300.0f, 4.64f},
    {400.0f, 4.28f},    {500.0f, 3.96f},    {600.0f, 3.63f},
    {700.0f, 3.28f},    {800.0f, 3.00f},    {900.0f, 2.78f},
    {1000.0f, 2.53f},   {1100.0f, 2.38f},   {1200.0f, 2.18f},
    {1300.0f, 2.04f},   {1400.0f, 1.92f},   {1500.0f, 1.76f},
    {1600.0f, 1.64f},   {1700.0f, 1.54f},   {1800.0f, 1.46f},
    {1900.0f, 1.38f},   {2000.0f, 1.27f},   {2100.0f, 1.20f},
    {2200.0f, 1.14f},   {2300.0f, 1.08f},   {2400.0f, 1.02f},
    {2500.0f, 0.96f},   {2600.0f, 0.92f},   {2700.0f, 0.89f},
    {2800.0f, 0.84f},   {2900.0f, 0.78f},   {3000.0f, 0.76f},
    {3100.0f, 0.77f},   {3200.0f, 0.73f},   {3300.0f, 0.69f},
    {3400.0f, 0.68f},   {3500.0f, 0.65f},   {3600.0f, 0.63f},
    {3700.0f, 0.60f},   {3800.0f, 0.58f},   {3900.0f, 0.56f},
    {4000.0f, 0.55f},   {4100.0f, 0.53f},   {4200.0f, 0.51f},
    {4300.0f, 0.49f},   {4400.0f, 0.48f},   {4500.0f, 0.45f},
    {4600.0f, 0.44f},   {4700.0f, 0.43f},   {4800.0f, 0.41f},
    {4900.0f, 0.40f},   {5000.0f, 0.39f},   {5100.0f, 0.38f},
    {5200.0f, 0.36f},   {5300.0f, 0.36f},   {5400.0f, 0.35f},
    {5500.0f, 0.33f},   {5600.0f, 0.32f},   {5700.0f, 0.32f},
    {5800.0f, 0.32f},   {5900.0f, 0.31f},   {6000.0f, 0.29f}
};

static const int g_lut_size = sizeof(g_gain_lut) / sizeof(g_gain_lut[0]);


float LUT_GetRequiredInputVpp(float target_freq_hz, float desired_output_vpp) {
    // 1. 检查频率是否在查找表的范围内
    if (target_freq_hz < g_gain_lut[0].freq_hz || target_freq_hz > g_gain_lut[g_lut_size - 1].freq_hz) {
        return -1.0f; // 返回错误代码，表示频率超出范围
    }

    // 2. 查找目标频率所在的区间
    const Lut_Point_t *p1 = NULL, *p2 = NULL;
    for (int i = 0; i < g_lut_size - 1; ++i) {
        if (target_freq_hz >= g_gain_lut[i].freq_hz && target_freq_hz <= g_gain_lut[i + 1].freq_hz) {
            p1 = &g_gain_lut[i];
            p2 = &g_gain_lut[i + 1];
            break;
        }
    }

    if (p1 == NULL) {
        // 如果频率恰好等于最后一个点的值，上面的循环找不到，在这里处理
        if(target_freq_hz == g_gain_lut[g_lut_size-1].freq_hz) {
             p1 = p2 = &g_gain_lut[g_lut_size-1];
        } else {
            return -1.0f; // 理论上不会发生
        }
    }

    // 3. 线性插值计算当前频率下的增益
    float gain;
    if (p1 == p2 || p1->freq_hz == p2->freq_hz) {
        gain = p1->vpp_gain;
    } else {
        // y = y1 + (x - x1) * (y2 - y1) / (x2 - x1)
        gain = p1->vpp_gain + (target_freq_hz - p1->freq_hz) * (p2->vpp_gain - p1->vpp_gain) / (p2->freq_hz - p1->freq_hz);
    }
    
    if (gain <= 0.001f) { // 防止除以一个非常小或零的数
        return -1.0f; 
    }

    // 4. 根据期望输出电压和增益，计算所需的输入电压
    // V_in = V_out_desired / Gain
    float required_input_vpp = desired_output_vpp / gain;

    return required_input_vpp;
}