// =================================================================================
// =    FILTER ANALYZER MODULE (Adapted for UNREGISTERED ROM Output)             =
// =================================================================================
// This version is simplified to work with ROMs that have combinational
// (unregistered) outputs, as generated in your provided files.

module filter_analyzer (
    input clk,
    input rst,

    // Control signals
    input start_analysis,      // Pulse to start a new analysis cycle
    input new_data_point_valid, // Pulse indicating a new (Freq, I, Q) point is ready
    
    // Input data from VNA
    input [31:0] freq_in,
    input signed [11:0] i_in,
    input signed [11:0] q_in,

    // Output results
    output reg [3:0] filter_type, // 0:Unknown, 1:LPF, 2:HPF, 3:BPF, 4:BRF
    output reg analysis_done      // Pulse indicating analysis is complete
);

    // Filter type definitions
    localparam TYPE_UNKNOWN = 4'd0;
    localparam TYPE_LPF     = 4'd1;
    localparam TYPE_HPF     = 4'd2;
    localparam TYPE_BPF     = 4'd3;
    localparam TYPE_BRF     = 4'd4;
    
    // Total number of sweep points (1kHz to 500kHz, 200Hz step)
    localparam LEARN_NUM_POINTS = 2495;

    // State machine for the analyzer
    localparam S_IDLE   = 2'd0;
    localparam S_CALC   = 2'd1;
    localparam S_DECIDE = 2'd2;
    reg [1:0] state;

    // =================================================================
    // === 1. Magnitude Calculation (using LUTs)           ===
    // =================================================================

    // --- Magnitude Calculation (SQRT LUT) ---
    wire signed [23:0] i_sq = i_in * i_in;
    wire signed [23:0] q_sq = q_in * q_in;
    wire [23:0] mag_sq = i_sq + q_sq;
    
    wire [11:0] sqrt_addr = mag_sq[23:12];
    wire [15:0] magnitude_out;

    // --- ROM Instantiation ---
    // This is now a direct, combinational connection.
    sqrt_rom u_sqrt_rom (
        .address (sqrt_addr), 
        .clock   (clk),       // Clock is still required by the IP
        .q       (magnitude_out)
    );
    
    // NOTE: The arctan_rom is not used in this version for simplicity,
    // as magnitude is sufficient for classification. You can add it back if needed.
    
    // =========================================================================
    // === 2. Feature Extraction and Main FSM                              ===
    // =========================================================================
    
    // --- Feature Storage ---
    reg [15:0] max_magnitude;
    reg [31:0] peak_freq;
    reg [15:0] min_magnitude;
    reg [15:0] dc_magnitude;   // Magnitude at the first frequency point
    reg [15:0] hf_magnitude;   // Magnitude at the last frequency point
    reg [11:0] data_point_counter; // Needs to hold up to 2495, so 12 bits

    // --- Decision Logic Thresholds ---
    wire [15:0] pass_threshold = min_magnitude + ((max_magnitude - min_magnitude) >> 1);
    wire [15:0] stop_threshold = pass_threshold;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            filter_type <= TYPE_UNKNOWN;
            analysis_done <= 1'b0;
            max_magnitude <= 0;
            peak_freq <= 0;
            min_magnitude <= 16'hFFFF;
            dc_magnitude <= 0;
            hf_magnitude <= 0;
            data_point_counter <= 0;
        end else begin
            analysis_done <= 1'b0; // Default to low

            case (state)
                S_IDLE: begin
                    if (start_analysis) begin
                        max_magnitude <= 0;
                        peak_freq <= 0;
                        min_magnitude <= 16'hFFFF;
                        dc_magnitude <= 0;
                        hf_magnitude <= 0;
                        data_point_counter <= 0;
                        filter_type <= TYPE_UNKNOWN;
                        state <= S_CALC;
                    end
                end

                S_CALC: begin
                    // Since the ROM is combinational, we can use the result in the same cycle
                    // that 'new_data_point_valid' is high. No pipeline needed.
                    if (new_data_point_valid) begin
                        if (magnitude_out > max_magnitude) begin
                            max_magnitude <= magnitude_out;
                            peak_freq <= freq_in;
                        end
                        if (magnitude_out < min_magnitude) begin
                            min_magnitude <= magnitude_out;
                        end
                        if (data_point_counter == 0) begin
                            dc_magnitude <= magnitude_out;
                        end
                        
                        if (data_point_counter == LEARN_NUM_POINTS - 1) begin
                            hf_magnitude <= magnitude_out;
                            state <= S_DECIDE;
                        end else begin
                            data_point_counter <= data_point_counter + 1;
                        end
                    end
                end

                S_DECIDE: begin
                    // Judgment logic
                    if (dc_magnitude > pass_threshold && hf_magnitude < stop_threshold) begin
                        filter_type <= TYPE_LPF;
                    end else if (dc_magnitude < stop_threshold && hf_magnitude > pass_threshold) begin
                        filter_type <= TYPE_HPF;
                    end else if (dc_magnitude < stop_threshold && hf_magnitude < stop_threshold) begin
                        filter_type <= TYPE_BPF;
                    end else if (dc_magnitude > pass_threshold && hf_magnitude > pass_threshold) begin
                        filter_type <= TYPE_BRF;
                    end else begin
                        filter_type <= TYPE_UNKNOWN;
                    end

                    analysis_done <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
