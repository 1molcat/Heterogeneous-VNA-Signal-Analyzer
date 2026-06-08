// bsp_fpga_control.h

#ifndef __BSP_FPGA_CONTROL_H__
#define __BSP_FPGA_CONTROL_H__
// --- START: ������Щͷ�ļ� ---
#include "bsp_fpga_control.h"
#include "main.h"            // ����STM32CubeMX���ɵ���Ŀ��main.hͨ����������б�Ҫ��HAL��ͷ�ļ�
#include <stdint.h>          // Ϊ�� uintX_t ����
#include <math.h>            // Ϊ�� round() ����
/**
 * @brief DAC����ģת��������������������ֵ��ѹ��
 * @note  ����һ��Ӳ�����ƣ����ڷ�ֹ���ó�����Χ�ĵ�ѹ��
 *        �˴�����Ϊ 5.0V�����������ʵ��Ӳ�������޸ġ�
 */
#define MAX_DAC_OUTPUT_VPP (5.0f)

/**
 * @brief ��ʼ��FPGA����ģ��
 * @note  ������FPGAͨ�������SPI/I2C�������ӿڡ�
 */
void FPGA_Init(void);

/**
 * @brief ����FPGA���ź����
 */
void FPGA_Output_Disable(void);

/**
 * @brief ����FPGA���һ����Ƶ���Ҳ�
 * @param freq_hz   Ƶ�ʣ���λ Hz��
 * @param amp_vpp   ���ֵ��ѹ����λ Vpp��
 * @param phase_deg ��λ����λ�� (���Ĵ�����δʹ�ã���ͨ�����д˲���)��
 */
void FPGA_Set_Single_SineWave(float freq_hz, float amp_vpp, float phase_deg); 

/**
 * @brief ����FPGA��ʼ�ڲ���VNAɨ��
 * @note  �˺�������FPGA��FPGA������Ԥ��Ĳ�����ʼɨƵ��
 *        ��ͨ�����ڷ���I/Q���ݡ�
 */
void FPGA_Start_VNA_Sweep(void);

/**
 * @brief ����FPGAֹͣVNAɨ��
 * @note  �������л�ģʽ����Ҫ��ֹɨ��ʱ����ǰ����FPGA��ɨƵ������
 */
void FPGA_Stop_VNA_Sweep(void);
void FPGA_Start_VNA_Sweep_With_Amp(float amp_vpp);
void FPGA_Start_Learning(void); // <<<--- 添加这一行

#endif // __BSP_FPGA_CONTROL_H__
