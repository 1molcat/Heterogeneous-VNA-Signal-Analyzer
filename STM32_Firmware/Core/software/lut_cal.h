#ifndef __LUT_CAL_H__
#define __LUT_CAL_H__

/**
 * @brief  ���������ĵ�·�����ѹ�͵�ǰƵ�ʣ�����FPGA��Ҫ�ṩ�������ѹ��
 * @param  target_freq_hz     ��ǰ�ź�Ƶ�� (Hz)
 * @param  desired_output_vpp �����ӡ���֪ģ�͵�·����õ�������ֵ��ѹ (V)
 * @retval float              FPGA��Ҫ���������Ҳ��ķ��ֵ��ѹ (V)�����Ƶ�ʳ�����Χ������-1.0��
 * @note   �ú���ʹ�����Բ�ֵ������߾��ȡ�
 */
float LUT_GetRequiredInputVpp(float target_freq_hz, float desired_output_vpp);

#endif // __LUT_CAL_H__

