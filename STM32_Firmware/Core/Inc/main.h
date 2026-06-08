/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.h
  * @brief          : Header for main.c file.
  *                   This file contains the common defines of the application.
  ******************************************************************************
  * @attention
  *
  * Copyright (c) 2025 STMicroelectronics.
  * All rights reserved.
  *
  * This software is licensed under terms that can be found in the LICENSE file
  * in the root directory of this software component.
  * If no LICENSE file comes with this software, it is provided AS-IS.
  *
  ******************************************************************************
  */
/* USER CODE END Header */

/* Define to prevent recursive inclusion -------------------------------------*/
#ifndef __MAIN_H
#define __MAIN_H

#ifdef __cplusplus
extern "C" {
#endif

/* Includes ------------------------------------------------------------------*/
#include "stm32f4xx_hal.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */

/* USER CODE END Includes */

/* Exported types ------------------------------------------------------------*/
/* USER CODE BEGIN ET */

/* USER CODE END ET */

/* Exported constants --------------------------------------------------------*/
/* USER CODE BEGIN EC */
// --- �������� ---
// 1. ��ͷ�ļ��ж��建������С�꣬�Ա������ļ�����ʹ��
#define HMI_RX_BUFFER_SIZE  64
#define FPGA_RX_BUFFER_SIZE 64

// 2. ʹ�� extern �ؼ�������ȫ�ֱ��������������ļ���Щ���������ڱ�
extern UART_HandleTypeDef huart1; // ��������ļ�Ҳ��Ҫ�����Լ���
extern UART_HandleTypeDef huart2; // ��������ļ�Ҳ��Ҫ�����Լ���
extern uint8_t g_hmi_rx_buffer[HMI_RX_BUFFER_SIZE];
extern uint8_t g_fpga_rx_buffer[FPGA_RX_BUFFER_SIZE];
/* USER CODE END EC */

/* Exported macro ------------------------------------------------------------*/
/* USER CODE BEGIN EM */

/* USER CODE END EM */

/* Exported functions prototypes ---------------------------------------------*/
void Error_Handler(void);

/* USER CODE BEGIN EFP */

/* USER CODE END EFP */

/* Private defines -----------------------------------------------------------*/

/* USER CODE BEGIN Private defines */

/* USER CODE END Private defines */

#ifdef __cplusplus
}
#endif

#endif /* __MAIN_H */
