// file: uart_rx.v (FINAL ROBUST VERSION with 16x Oversampling)
module uart_rx #(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD_RATE = 115200
)(
    input            clk,
    input            rst, // 高电平有效复位
    input            rxd,
    output reg [7:0] data_out,
    output reg       data_valid
);

    // ------------------- 1. 波特率时钟生成 -------------------
    // 我们需要一个频率为 BAUD_RATE * 16 的采样时钟
    localparam BAUD_X16_CLK_DIV = (CLK_FREQ / (BAUD_RATE * 16));
    
    reg [15:0] clk_divider_cnt = 0;
    reg baud_x16_tick = 0; // 这个信号会在每个 1/16 比特时间产生一个高脉冲

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_divider_cnt <= 0;
            baud_x16_tick <= 0;
        end else begin
            if (clk_divider_cnt == BAUD_X16_CLK_DIV - 1) begin
                clk_divider_cnt <= 0;
                baud_x16_tick <= 1;
            end else begin
                clk_divider_cnt <= clk_divider_cnt + 1;
                baud_x16_tick <= 0;
            end
        end
    end

    // ------------------- 2. 状态机和逻辑 -------------------
    // 状态定义
    localparam S_IDLE = 3'd0, S_START = 3'd1, S_DATA = 3'd2, S_STOP = 3'd3;
    reg [2:0] state = S_IDLE;

    // 内部计数器和寄存器
    reg [3:0] sample_cnt; // 用于在16个采样点中计数 (0 to 15)
    reg [3:0] bit_cnt;    // 用于对8个数据位计数 (0 to 7)
    reg [7:0] rx_data_reg;

    // 为异步输入rxd创建同步器
    reg rxd_sync1 = 1, rxd_sync2 = 1, rxd_sync3 = 1;
    always @(posedge clk) begin
        rxd_sync1 <= rxd;
        rxd_sync2 <= rxd_sync1;
        rxd_sync3 <= rxd_sync2; // 使用三级同步器增加鲁棒性
    end
    
    // 主状态机，由 baud_x16_tick 驱动
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            data_valid <= 0;
            sample_cnt <= 0;
            bit_cnt <= 0;
            data_out <= 0;
        end else begin
            data_valid <= 0; // 默认拉低，产生单周期脉冲

            if (baud_x16_tick) begin // 只在采样时钟有效时才动作
                case (state)
                    S_IDLE: begin
                        // 在空闲状态，持续寻找下降沿（起始位）
                        if (rxd_sync3 == 1'b0) begin
                            state <= S_START;
                            sample_cnt <= 0; // 开始对16个采样点计数
                        end
                    end

                    S_START: begin
                        // 在起始位状态，计数到比特中间 (第7或第8个采样点)
                        if (sample_cnt == 7) begin
                            // 在中心点再次确认是否为低电平，滤除毛刺
                            if (rxd_sync3 == 1'b0) begin
                                state <= S_DATA;
                                sample_cnt <= 0; // 为接收数据位复位采样计数
                                bit_cnt <= 0;    // 开始接收第0位
                            end else begin
                                state <= S_IDLE; // 是毛刺，返回空闲
                            end
                        end else begin
                            sample_cnt <= sample_cnt + 1;
                        end
                    end

                    S_DATA: begin
                        // 在数据位状态，等待每个比特的中心采样点
                        if (sample_cnt == 15) begin
                            sample_cnt <= 0;
                            // 在中心点(15->0的转换点之前)采样数据
                            // LSB first: {new_bit, old_data[7:1]}
                            rx_data_reg <= {rxd_sync3, rx_data_reg[7:1]};
                            
                            if (bit_cnt == 7) begin
                                state <= S_STOP; // 8位接收完毕
                            end else begin
                                bit_cnt <= bit_cnt + 1;
                            end
                        end else begin
                            sample_cnt <= sample_cnt + 1;
                        end
                    end

                    S_STOP: begin
                        // 在停止位状态，等待中心采样点
                        if (sample_cnt == 15) begin
                            // (此处可以检查rxd_sync3是否为1来报帧错误)
                            data_out <= rx_data_reg;
                            data_valid <= 1;
                            state <= S_IDLE; // 接收完成，返回空闲
                        end else begin
                            sample_cnt <= sample_cnt + 1;
                        end
                    end
                endcase
            end
        end
    end

endmodule
