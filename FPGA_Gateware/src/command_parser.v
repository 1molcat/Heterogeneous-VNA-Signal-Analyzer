// --- START OF MODIFIED FILE command_parser_simple.v (FOR 47 BYTES) ---

module command_parser_simple (
    input           clk,
    input           rst,
    input    [7:0]  uart_data,
    input           uart_valid,
    output reg      cmd_received,
    // MODIFIED: Bus width is now 47*8 = 376 bits
    output   [375:0] received_bus_flat,
    output reg      data_ready_for_tx
);

    // MODIFIED: Byte count now needs more bits, e.g., 6 bits for up to 63
    reg [5:0] byte_count; 
    // MODIFIED: Buffer now holds 47 bytes
    reg [7:0] data_buffer [0:46]; 

    // Use a generate block to flatten the buffer into the output bus
    genvar i;
    generate
        for (i = 0; i < 47; i = i + 1) begin: pack_bytes
            assign received_bus_flat[(i*8)+7 : i*8] = data_buffer[i];
        end
    endgenerate

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            byte_count <= 0;
            cmd_received <= 1'b0;
            data_ready_for_tx <= 1'b0;
        end else begin
            // Pulses should be held for one cycle only
            cmd_received <= 1'b0;
            data_ready_for_tx <= 1'b0;
            
            if (uart_valid) begin
                if (byte_count == 0) begin // State: IDLE, waiting for start byte
                    if (uart_data == 8'hA5) begin
                        data_buffer[0] <= uart_data;
                        byte_count <= 1;
                    end
                end 
                else if (byte_count < 46) begin // State: RECEIVING DATA
                    data_buffer[byte_count] <= uart_data;
                    byte_count <= byte_count + 1;
                end 
                else begin // State: LAST BYTE (byte_count == 46)
                    data_buffer[46] <= uart_data;
                    // Check for the footer byte
                    if (uart_data == 8'h5A) begin
                        cmd_received <= 1'b1;
                        data_ready_for_tx <= 1'b1;
                    end
                    byte_count <= 0; // Reset to IDLE state
                end
            end
        end
    end

endmodule
// --- END OF MODIFIED FILE ---