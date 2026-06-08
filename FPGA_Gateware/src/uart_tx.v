// --- START OF FILE uart_tx.v ---
// (FINAL, CORRECTED FORMAT AND LOGIC)

module uart_tx #(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD_RATE = 115200
)(
    input                 clk,
    input                 rst,
    input                 tx_start,
    input        [7:0]    tx_data_in,
    output                tx_busy,
    output reg            txd
);

    localparam CLK_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam S_IDLE = 2'd0, S_START = 2'd1, S_DATA = 2'd2, S_STOP = 2'd3;
    
    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [3:0]  bit_cnt;
    reg [9:0]  tx_shift_reg;

    assign tx_busy = (state != S_IDLE);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            txd <= 1'b1;
            clk_cnt <= 0;
            bit_cnt <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    txd <= 1'b1;
                    if (tx_start) begin
                        tx_shift_reg <= {1'b1, tx_data_in, 1'b0};
                        clk_cnt <= 0;
                        bit_cnt <= 0;
                        state <= S_START;
                    end
                end
                S_START: begin
                    txd <= tx_shift_reg[0];
                    if (clk_cnt == CLK_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        bit_cnt <= bit_cnt + 1;
                        state <= S_DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end
                S_DATA: begin
                    txd <= tx_shift_reg[bit_cnt];
                    if (clk_cnt == CLK_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        if (bit_cnt == 8) begin
                            state <= S_STOP;
                        end
                        bit_cnt <= bit_cnt + 1;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end
                S_STOP: begin
                    txd <= tx_shift_reg[9];
                    if (clk_cnt == CLK_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        state <= S_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end
                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
// --- END OF FILE uart_tx.v ---
