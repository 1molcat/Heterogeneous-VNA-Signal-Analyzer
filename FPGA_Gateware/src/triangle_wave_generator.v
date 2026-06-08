// --- START OF FILE triangle_wave_generator.v ---
// (CORRECTED for 14-bit output)

module triangle_wave_generator #(
    parameter ACCU_WIDTH = 32,
    parameter DATA_WIDTH = 14
)(
    input                      clk,
    input                      rst,
    
    input  [ACCU_WIDTH-1:0]    freq_word_in,
    input  [ACCU_WIDTH-1:0]    phase_offset_in,
    
    output [DATA_WIDTH-1:0]    data_out
);

    reg [ACCU_WIDTH-1:0] phase_accumulator;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            phase_accumulator <= 0;
        end else begin
            phase_accumulator <= phase_accumulator + freq_word_in;
        end
    end

    wire [ACCU_WIDTH-1:0] phase_with_offset = phase_accumulator + phase_offset_in;
    
    // ================== KEY FIX HERE ==================
    // For a 14-bit output (DATA_WIDTH=14), we need 15 bits for phase control.
    // So the vector should be declared as [DATA_WIDTH:0], which is [14:0].
    wire [DATA_WIDTH:0] top_phase_bits = phase_with_offset[ACCU_WIDTH-1 : ACCU_WIDTH-1-DATA_WIDTH];
    // ================================================
    
    // The logic is now correct:
    // top_phase_bits[14] is the direction bit.
    // top_phase_bits[13:0] are the value bits.
    assign data_out = (top_phase_bits[DATA_WIDTH] == 1'b0) ? top_phase_bits[DATA_WIDTH-1:0] : ~top_phase_bits[DATA_WIDTH-1:0];

endmodule
// --- END OF FILE triangle_wave_generator.v ---