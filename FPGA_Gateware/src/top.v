// =================================================================================
// =         FINAL INTEGRATED VERSION: Multi-Harmonic Stimulus & VNA (Corrected v4) =
// =================================================================================
// This version combines a multi-harmonic arbitrary waveform generator with a
// vector network analyzer front-end.
//
// Key Features:
// - Multi-Harmonic Excitation: Generates a stimulus signal composed of a fundamental
//   frequency and up to 9 of its harmonics, each with configurable amplitude and phase.
// - Coherent Sweeping: Sweeps the fundamental frequency of the complex waveform.
// - Coherent Demodulation: Measures the system's response by performing IQ demodulation
//   referenced to the fundamental frequency of the sweep.
// - High-SNR Measurement: Employs coherent averaging over 64 cycles after a 64-cycle
//   stabilization period at each frequency step.
// - Robust Data Link: Uses a FIFO and a dedicated UART transmitter to send
//   (Frequency, I_avg, Q_avg) data packets to the host PC.
//
// MODIFIED TO INCLUDE:
// - Filter Analyzer: Learns the frequency response of an unknown filter.
// - Type Judgment: Determines the filter type (LPF, HPF, BPF, BRF).
// - UART Result Reporting: Sends the determined filter type to a host.
// =================================================================================

module top (
    input             sys_clk,
    input             sys_rst,
    input             uart_rxd,
    output            adc_clk,
    input  [11:0]     adc_din,
    output            dac1_out, 
    output reg [13:0] dac2_out,
    output            da1_clk,
    output            da1_wrt,
    output            da2_clk,
    output            da2_wrt,
    output            uart_txd
);

    // =================================================================
    // === 0. PLL, RESET, AND CLOCKS                                 ===
    // =================================================================
    wire clk_data;
    wire pll_locked;
    my_pll u_my_pll (.inclk0(sys_clk), .areset(sys_rst), .c0(clk_data), .locked(pll_locked));
    wire effective_rst = sys_rst | ~pll_locked;

    assign adc_clk = clk_data;
    assign dac1_out = 14'h2000;
    assign da1_clk  = 1'b0;
    assign da1_wrt  = 1'b0;

    // =================================================================
    // === 1. UART COMMAND PARSER                                    ===
    // =================================================================
    wire [7:0]  uart_byte;
    wire        uart_byte_valid;
    wire        cmd_received_pulse;
    wire [375:0] received_data_flat_bus;
    
    uart_rx #(.CLK_FREQ(50_000_000), .BAUD_RATE(115200)) u_uart_rx (.clk(clk_data), .rst(effective_rst), .rxd(uart_rxd),.data_out(uart_byte), .data_valid(uart_byte_valid));
    command_parser_simple u_command_parser_simple (.clk(clk_data), .rst(effective_rst), .uart_data(uart_byte), .uart_valid(uart_byte_valid),.cmd_received(cmd_received_pulse), .received_bus_flat(received_data_flat_bus));

    // =================================================================================
    // === 1.5. GLOBAL CONTROL AND LEARNING PARAMETERS                               ===
    // =================================================================================

    // --- Main Control State Machine ---
    localparam FSM_IDLE      = 2'd0; // Waiting for commands
    localparam FSM_LEARN     = 2'd1; // Learning the filter (sweeping and analyzing)
    localparam FSM_REPRODUCE = 2'd2; // Reserved for future use (waveform reproduction)

    reg [1:0] main_fsm_state;

    // --- Learning Sweep Parameters (1kHz to 500kHz, 200Hz step) ---
    localparam LEARN_START_FREQ_WORD = 32'd85899;      // ~1kHz
    localparam LEARN_STEP_FREQ_WORD  = 32'd17180;      // ~200Hz
    localparam LEARN_STOP_FREQ_WORD  = 32'd42949673;   // ~500kHz (CORRECTED)
    localparam LEARN_NUM_POINTS      = 2495;           // Number of points to sweep (CORRECTED)

    // --- New UART command trigger for learning (assuming command ID 6) ---
    wire learn_start_trigger = cmd_received_pulse && (received_data_flat_bus[15:8] == 8'd6); 

    // =================================================================================
    // === 2. PARAMETER STORAGE & ADVANCED SWEEP CONTROLLER                          ===
    // =================================================================================
    
    localparam S_IDLE      = 1'b0;
    localparam S_SWEEPING  = 1'b1;

    localparam DWELL_TOTAL_CYCLES  = 128;
    localparam DWELL_STABLE_CYCLES = 64;
    localparam DWELL_MEASURE_CYCLES = 64; // Explicit measurement cycles
    
    // --- Original VNA sweep parameters ---
    localparam START_FREQ_WORD     = 32'd17180;
    localparam STEP_FREQ_WORD      = 32'd17180;
    localparam STOP_FREQ_WORD      = 32'd42949673;

    reg  sweep_state;
    reg  output_enable_reg;
    reg [31:0] sweep_freq_word_reg;
    reg [31:0] ch2_phase_accumulator;
    reg [31:0] ch2_phase_accumulator_prev; // Added for better cycle detection
    reg [7:0]  dwell_cycle_counter;
    reg [7:0]  actual_cycles_counted; // Added to track actual cycles

    wire [7:0]  rx_command_id = received_data_flat_bus[15:8];
    wire static_wave_set_trigger = cmd_received_pulse && (rx_command_id == 2);
    wire output_disable_trigger  = cmd_received_pulse && (rx_command_id == 3);
    wire sweep_stop_trigger      = cmd_received_pulse && (rx_command_id == 4);
    wire sweep_start_trigger     = cmd_received_pulse && (rx_command_id == 5);

    wire [31:0] rx_freq_word_arg   = {received_data_flat_bus[47:40], received_data_flat_bus[39:32], received_data_flat_bus[31:24], received_data_flat_bus[23:16]};
    wire [15:0] rx_vna_amp_arg     = {received_data_flat_bus[31:24], received_data_flat_bus[23:16]};
    
    reg [31:0] ch2_base_freq_word_reg;
    reg [15:0] ch2_amplitudes [0:9];
    reg [15:0] ch2_phases     [0:9];

    // Improved cycle detection - detects MSB transition from 1 to 0
    wire cycle_tick = (sweep_state == S_SWEEPING) && 
                      (ch2_phase_accumulator_prev[31] == 1'b1) && 
                      (ch2_phase_accumulator[31] == 1'b0);
    
    wire send_avg_data_pulse = (cycle_tick && (dwell_cycle_counter == DWELL_TOTAL_CYCLES - 1));

    // --- SWEEP CONTROL LOGIC ---
    always @(posedge clk_data or posedge effective_rst) begin
        if (effective_rst) begin
            sweep_state <= S_IDLE;
            output_enable_reg <= 1'b0;
            sweep_freq_word_reg <= 32'd0;
            ch2_phase_accumulator <= 32'd0;
            ch2_phase_accumulator_prev <= 32'd0;
            dwell_cycle_counter <= 8'd0;
            actual_cycles_counted <= 8'd0;
        end else begin
            // Phase accumulator logic
            ch2_phase_accumulator_prev <= ch2_phase_accumulator;
            
            if (sweep_state == S_SWEEPING) begin
                ch2_phase_accumulator <= ch2_phase_accumulator + sweep_freq_word_reg;
            end

            // Dwell counter and frequency step logic
            if (send_avg_data_pulse) begin
                dwell_cycle_counter <= 8'd0;
                actual_cycles_counted <= 8'd0;
                // Check if we are in learning mode or normal sweep mode
                if (main_fsm_state == FSM_LEARN) begin
                    if (sweep_freq_word_reg < LEARN_STOP_FREQ_WORD) begin
                        sweep_freq_word_reg <= sweep_freq_word_reg + LEARN_STEP_FREQ_WORD;
                    end else begin
                        sweep_state <= S_IDLE; // Stop sweeping when learning sweep is done
                    end
                end else begin // Normal VNA sweep
                    if (sweep_freq_word_reg < STOP_FREQ_WORD) begin
                        sweep_freq_word_reg <= sweep_freq_word_reg + STEP_FREQ_WORD;
                    end else begin
                         sweep_state <= S_IDLE; // Stop sweeping
                    end
                end
            end else if (cycle_tick) begin
                dwell_cycle_counter <= dwell_cycle_counter + 1;
                if (dwell_cycle_counter >= DWELL_STABLE_CYCLES) begin
                    actual_cycles_counted <= actual_cycles_counted + 1;
                end
            end

            // State control triggers
            if (learn_start_trigger && main_fsm_state == FSM_IDLE) begin
                sweep_state <= S_SWEEPING;
                output_enable_reg <= 1'b1;
                sweep_freq_word_reg <= LEARN_START_FREQ_WORD;
                ch2_phase_accumulator <= 32'd0;
                ch2_phase_accumulator_prev <= 32'd0;
                dwell_cycle_counter <= 8'd0;
                actual_cycles_counted <= 8'd0;
            end else if (sweep_start_trigger && main_fsm_state == FSM_IDLE) begin
                sweep_state <= S_SWEEPING;
                output_enable_reg <= 1'b1;
                sweep_freq_word_reg <= START_FREQ_WORD;
                ch2_phase_accumulator <= 32'd0;
                ch2_phase_accumulator_prev <= 32'd0;
                dwell_cycle_counter <= 8'd0;
                actual_cycles_counted <= 8'd0;
            end else if (sweep_stop_trigger) begin
                sweep_state <= S_IDLE;
                output_enable_reg <= 1'b0;
            end else if (output_disable_trigger) begin
                sweep_state <= S_IDLE;
                output_enable_reg <= 1'b0;
            end else if (static_wave_set_trigger) begin
                if (sweep_state == S_IDLE) begin
                    output_enable_reg <= 1'b1;
                end
            end
        end
    end

    // --- Harmonic amplitude and phase setting ---
    always @(posedge clk_data or posedge effective_rst) begin
        integer j;
        if (effective_rst) begin
            ch2_base_freq_word_reg <= 0;
            for (j = 0; j < 10; j = j + 1) begin
                ch2_amplitudes[j] <= (j==0) ? 16'hFFFF : 16'h0;
                ch2_phases[j]     <= 0;
            end
        end else begin
            if ((sweep_start_trigger && main_fsm_state != FSM_LEARN) || (learn_start_trigger)) begin
                ch2_amplitudes[0] <= rx_vna_amp_arg;
                for (j = 1; j < 10; j = j + 1) begin
                    ch2_amplitudes[j] <= 16'h0;
                    ch2_phases[j]     <= 16'h0;
                end
            end else if (static_wave_set_trigger) begin
                ch2_base_freq_word_reg <= rx_freq_word_arg;
                ch2_amplitudes[0] <= {received_data_flat_bus[63:56], received_data_flat_bus[55:48]};
                ch2_phases[0]     <= {received_data_flat_bus[79:72], received_data_flat_bus[71:64]};
                ch2_amplitudes[1] <= {received_data_flat_bus[95:88], received_data_flat_bus[87:80]};
                ch2_phases[1]     <= {received_data_flat_bus[111:104], received_data_flat_bus[103:96]};
                ch2_amplitudes[2] <= {received_data_flat_bus[127:120], received_data_flat_bus[119:112]};
                ch2_phases[2]     <= {received_data_flat_bus[143:136], received_data_flat_bus[135:128]};
                ch2_amplitudes[3] <= {received_data_flat_bus[159:152], received_data_flat_bus[151:144]};
                ch2_phases[3]     <= {received_data_flat_bus[175:168], received_data_flat_bus[167:160]};
                ch2_amplitudes[4] <= {received_data_flat_bus[191:184], received_data_flat_bus[183:176]};
                ch2_phases[4]     <= {received_data_flat_bus[207:200], received_data_flat_bus[199:192]};
                ch2_amplitudes[5] <= {received_data_flat_bus[223:216], received_data_flat_bus[215:208]};
                ch2_phases[5]     <= {received_data_flat_bus[239:232], received_data_flat_bus[231:224]};
                ch2_amplitudes[6] <= {received_data_flat_bus[255:248], received_data_flat_bus[247:240]};
                ch2_phases[6]     <= {received_data_flat_bus[271:264], received_data_flat_bus[263:256]};
                ch2_amplitudes[7] <= {received_data_flat_bus[287:280], received_data_flat_bus[279:272]};
                ch2_phases[7]     <= {received_data_flat_bus[303:296], received_data_flat_bus[295:288]};
                ch2_amplitudes[8] <= {received_data_flat_bus[319:312], received_data_flat_bus[311:304]};
                ch2_phases[8]     <= {received_data_flat_bus[335:328], received_data_flat_bus[327:320]};
                ch2_amplitudes[9] <= {received_data_flat_bus[351:344], received_data_flat_bus[343:336]};
                ch2_phases[9]     <= {received_data_flat_bus[367:360], received_data_flat_bus[359:352]};
            end

            if (sweep_state == S_SWEEPING) begin
                ch2_base_freq_word_reg <= sweep_freq_word_reg;
            end
        end
    end

    // =================================================================
    // === 3. HARMONIC SYNTHESIS CORE                                ===
    // =================================================================
    wire signed [13:0] ch2_sine_harmonics [0:9];
        genvar m;
    generate 
        for (m = 0; m < 10; m = m + 1) begin: ch2_harmonic_gen
            dds_ip u_dds2_h_inst (
                .clk(clk_data), .reset_n(~effective_rst), .clken(1'b1),
                .phi_inc_i(ch2_base_freq_word_reg * (m+1)), 
                .phase_mod_i(ch2_phases[m]), .fsin_o(ch2_sine_harmonics[m]), .out_valid()
            );
        end
    endgenerate

    // =================================================================
    // === 4. PIPELINED SUMMATION & SCALING                          ===
    // =================================================================
    localparam MID_POINT_14_BIT = 14'h2000;
    assign da2_wrt = clk_data; 
    assign da2_clk = clk_data;

    reg signed [30:0] ch2_products_s1 [0:9];
    reg signed [31:0] ch2_sum_s2 [0:4];
    reg signed [32:0] ch2_sum_s3 [0:1];
    reg signed [32:0] ch2_sum_s3_single;
    reg signed [34:0] ch2_final_sum_s4;

    integer i;
    always @(posedge clk_data or posedge effective_rst) begin
        if (effective_rst) begin
            for(i=0; i<10; i=i+1) begin ch2_products_s1[i] <= 0; end
            for(i=0; i<5; i=i+1)  begin ch2_sum_s2[i] <= 0;      end
            for(i=0; i<2; i=i+1)  begin ch2_sum_s3[i] <= 0;      end
            ch2_sum_s3_single <= 0;
            ch2_final_sum_s4  <= 0;
            dac2_out <= MID_POINT_14_BIT;
        end else begin
            for (i = 0; i < 10; i = i + 1) begin
                ch2_products_s1[i] <= ch2_sine_harmonics[i] * $signed({1'b0, ch2_amplitudes[i]});
            end
            
            ch2_sum_s2[0] <= ch2_products_s1[0] + ch2_products_s1[1];
            ch2_sum_s2[1] <= ch2_products_s1[2] + ch2_products_s1[3];
            ch2_sum_s2[2] <= ch2_products_s1[4] + ch2_products_s1[5];
            ch2_sum_s2[3] <= ch2_products_s1[6] + ch2_products_s1[7];
            ch2_sum_s2[4] <= ch2_products_s1[8] + ch2_products_s1[9];

            ch2_sum_s3[0] <= ch2_sum_s2[0] + ch2_sum_s2[1];
            ch2_sum_s3[1] <= ch2_sum_s2[2] + ch2_sum_s2[3];
            ch2_sum_s3_single <= ch2_sum_s2[4];

            ch2_final_sum_s4 <= ch2_sum_s3[0] + ch2_sum_s3[1] + ch2_sum_s3_single;

            dac2_out <= output_enable_reg ? (ch2_final_sum_s4[34:16] + MID_POINT_14_BIT) : MID_POINT_14_BIT;
        end
    end

    // =================================================================================
    // === 5. IQ DEMODULATOR with ACCUMULATORS (CORRECTED)                           ===
    // =================================================================================
    reg  [31:0] ch2_phase_accumulator_dly;
    wire [1:0]  current_quadrant = ch2_phase_accumulator[31:30];
    wire [1:0]  prev_quadrant    = ch2_phase_accumulator_dly[31:30];
    wire        sample_trigger = (current_quadrant != prev_quadrant) && (sweep_state == S_SWEEPING);

    reg  [11:0] adc_data_reg;
    wire signed [11:0] adc_data_signed = adc_data_reg - 12'h800;

    reg signed [11:0] i_sample_reg, q_sample_reg;
    reg               iq_pair_ready_pulse;

    reg signed [23:0] i_accumulator;
    reg signed [23:0] q_accumulator;
    
    // IQ sampling state machine
    always @(posedge clk_data or posedge effective_rst) begin
        if(effective_rst) begin
            ch2_phase_accumulator_dly <= 32'd0;
            adc_data_reg <= 12'd0;
            i_sample_reg <= 12'd0;
            q_sample_reg <= 12'd0;
            iq_pair_ready_pulse <= 1'b0;
        end else begin
            ch2_phase_accumulator_dly <= ch2_phase_accumulator;
            adc_data_reg <= adc_din;
            iq_pair_ready_pulse <= 1'b0;
            if (sample_trigger) begin
                case(prev_quadrant)
                    2'b00: q_sample_reg <=  adc_data_signed;
                    2'b01: i_sample_reg <= -adc_data_signed;
                    2'b10: q_sample_reg <= -adc_data_signed;
                    2'b11: begin
                        i_sample_reg <= adc_data_signed;
                        iq_pair_ready_pulse <= 1'b1;
                    end
                endcase
            end
        end
    end

    // CORRECTED: Accumulator logic - only accumulate during measurement phase
    always @(posedge clk_data or posedge effective_rst) begin
        if (effective_rst) begin
            i_accumulator <= 24'd0;
            q_accumulator <= 24'd0;
        end else begin
            // Reset accumulators at the start of each frequency step
            if (cycle_tick && dwell_cycle_counter == 0) begin 
                i_accumulator <= 24'd0;
                q_accumulator <= 24'd0;
            end 
            // Only accumulate during measurement phase (after stabilization)
            else if (iq_pair_ready_pulse && (dwell_cycle_counter >= DWELL_STABLE_CYCLES)) begin
                i_accumulator <= i_accumulator + $signed(i_sample_reg);
                q_accumulator <= q_accumulator + $signed(q_sample_reg);
            end
        end
    end

    // =================================================================================
    // === 5.5. FILTER ANALYZER & FREQUENCY RESPONSE STORAGE                         ===
    // =================================================================================
    
    wire [3:0] filter_type_out;
    wire analysis_done_pulse;

    filter_analyzer u_filter_analyzer (
    .clk(clk_data),
    .rst(effective_rst),
    .start_analysis(learn_start_trigger),
    // Use the signal that indicates a full average is complete
    .new_data_point_valid(send_avg_data_pulse && (main_fsm_state == FSM_LEARN)), 
    .freq_in(sweep_freq_word_reg),
    .i_in(i_avg), // Connect the 12-bit averaged I value
    .q_in(q_avg), // Connect the 12-bit averaged Q value
    .filter_type(filter_type_out),
    .analysis_done(analysis_done_pulse)
);

    // --- Main FSM Logic ---
    always @(posedge clk_data or posedge effective_rst) begin
        if (effective_rst) begin
            main_fsm_state <= FSM_IDLE;
        end else begin
            case(main_fsm_state)
                FSM_IDLE: begin
                    if (learn_start_trigger) begin
                        main_fsm_state <= FSM_LEARN;
                    end
                end
                FSM_LEARN: begin
                    if (analysis_done_pulse) begin
                        main_fsm_state <= FSM_IDLE; // Learning complete, return to idle
                    end
                end
                FSM_REPRODUCE: begin
                    // Placeholder for future logic
                end
                default: main_fsm_state <= FSM_IDLE;
            endcase
        end
    end

    // =================================================================================
    // === 6. FIFO INTERFACE and DATA PACKAGING                                      ===
    // =================================================================================
    localparam FIFO_WIDTH = 64;
    wire [FIFO_WIDTH-1:0] fifo_wdata;
    wire                  fifo_wr_en;
    wire [FIFO_WIDTH-1:0] fifo_rdata;
    wire                  fifo_full;
    wire                  fifo_empty;
    wire                  fifo_rd_en;
    
    // CORRECTED: Average calculation based on actual measured cycles
 wire signed [11:0] i_avg = $signed(i_accumulator) >>> 6;
    wire signed [11:0] q_avg = $signed(q_accumulator) >>> 6;

    wire signed [15:0] i_extended = {{4{i_avg[11]}}, i_avg};
    wire signed [15:0] q_extended = {{4{q_avg[11]}}, q_avg};

    // Only write to FIFO if not in learning mode
    assign fifo_wr_en = send_avg_data_pulse && !fifo_full && (main_fsm_state != FSM_LEARN);
    assign fifo_wdata = {sweep_freq_word_reg, q_extended, i_extended};

    fifo iq_fifo ( 
        .clock(clk_data), 
        .data(fifo_wdata), 
        .rdreq(fifo_rd_en), 
        .wrreq(fifo_wr_en), 
        .empty(fifo_empty), 
        .full(fifo_full), 
        .q(fifo_rdata), 
        .usedw()
    );

    // =================================================================================
    // === 7. DEDICATED UART SENDER                                                  ===
    // =================================================================================
    reg [3:0]  tx_state;
    localparam TX_IDLE = 4'd0, TX_SEND_BYTE = 4'd1, TX_SEND_TYPE = 4'd2;
    reg [3:0]  tx_byte_idx;
    reg [7:0]  tx_data_to_send;
    reg        tx_start_pulse;
    wire       tx_is_busy;
    reg        tx_is_busy_dly;
    wire       tx_finished_pulse = tx_is_busy_dly & !tx_is_busy;
    reg [FIFO_WIDTH-1:0] tx_packet_reg;

    // Signal to trigger sending the filter type
    reg tx_send_type_trigger;
    always @(posedge clk_data) begin
        tx_send_type_trigger <= analysis_done_pulse;
    end

    uart_tx #(.CLK_FREQ(50_000_000), .BAUD_RATE(115200)) u_uart_tx (
        .clk(clk_data), 
        .rst(effective_rst), 
        .tx_start(tx_start_pulse), 
        .tx_data_in(tx_data_to_send),
        .tx_busy(tx_is_busy), 
        .txd(uart_txd)
    );
    
    // FIFO read enable logic
    assign fifo_rd_en = (tx_state == TX_IDLE) && !fifo_empty && !tx_is_busy;

    // UART transmit FSM
    always @(posedge clk_data or posedge effective_rst) begin
        if(effective_rst) begin
            tx_state <= TX_IDLE;
            tx_byte_idx <= 4'd0;
            tx_start_pulse <= 1'b0;
            tx_is_busy_dly <= 1'b0;
            tx_packet_reg <= 64'd0;
        end else begin
            tx_is_busy_dly <= tx_is_busy;
            tx_start_pulse <= 1'b0; // Default to low

            case(tx_state)
                TX_IDLE: begin
                    if (fifo_rd_en) begin // Original VNA data sending
                        tx_packet_reg <= fifo_rdata;
                        tx_byte_idx <= 4'd0;
                        tx_start_pulse <= 1'b1;
                        tx_state <= TX_SEND_BYTE;
                    end else if (tx_send_type_trigger && !tx_is_busy) begin // Send analysis result
                        tx_byte_idx <= 4'd0;
                        tx_start_pulse <= 1'b1;
                        tx_state <= TX_SEND_TYPE;
                    end
                end

                TX_SEND_BYTE: begin // Original state for sending VNA packet
                    if (tx_finished_pulse) begin
                        if (tx_byte_idx == 9) begin
                            tx_state <= TX_IDLE;
                        end else begin
                            tx_byte_idx <= tx_byte_idx + 1;
                            tx_start_pulse <= 1'b1;
                        end
                    end
                end
            
                TX_SEND_TYPE: begin // State for sending filter type packet
                    if (tx_finished_pulse) begin
                        if (tx_byte_idx == 2) begin // Packet is: Header, Type, Footer
                            tx_state <= TX_IDLE;
                        end else begin
                            tx_byte_idx <= tx_byte_idx + 1;
                            tx_start_pulse <= 1'b1;
                        end
                    end
                end
                
                default: begin
                    tx_state <= TX_IDLE;
                end
            endcase
        end
    end
 
    // Data MUX for transmitter
    always @(*) begin
        case(tx_state)
            TX_SEND_BYTE: begin
                case(tx_byte_idx)
                    0: tx_data_to_send = 8'hA5; // VNA data header
                    1: tx_data_to_send = tx_packet_reg[63:56];
                    2: tx_data_to_send = tx_packet_reg[55:48];
                    3: tx_data_to_send = tx_packet_reg[47:40];
                    4: tx_data_to_send = tx_packet_reg[39:32];
                    5: tx_data_to_send = tx_packet_reg[31:24];
                    6: tx_data_to_send = tx_packet_reg[23:16];
                    7: tx_data_to_send = tx_packet_reg[15:8];
                    8: tx_data_to_send = tx_packet_reg[7:0];
                    9: tx_data_to_send = 8'h5A; // VNA data footer
                    default: tx_data_to_send = 8'h00;
                endcase
            end
            TX_SEND_TYPE: begin
                case(tx_byte_idx)
                    0: tx_data_to_send = 8'hB5;                   // New header for filter type
                    1: tx_data_to_send = {4'h0, filter_type_out}; // The 4-bit filter type
                    2: tx_data_to_send = 8'h5B;                   // New footer
                    default: tx_data_to_send = 8'h00;
                endcase
            end
            default: tx_data_to_send = 8'h00;
        endcase
    end

endmodule
