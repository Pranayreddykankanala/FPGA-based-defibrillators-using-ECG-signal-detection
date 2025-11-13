`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Modified top_module.v - adds VT and VF detection using RR intervals
//////////////////////////////////////////////////////////////////////////////////

module top_module(
    input wire clk,
    input wire rst,
    input wire SWr,
    input wire Sig,    // R-peak input (synchronized externally or by this module)
    input wire Wr,     // write control
    output wire [7:0] RR_int_ms,
    output wire [7:0] HIGH,
    output wire [7:0] NORMAL,
    output wire [7:0] LOW,
    output wire VT,    // 1 when Ventricular Tachycardia detected
    output wire VF     // 1 when Ventricular Fibrillation detected
);

    // --- parameters (tune these for your timebase) ---
    localparam integer WINDOW_SIZE = 8;
    localparam [7:0] VT_THRESHOLD = 8'd40;        // intervals smaller than this count -> "short" (tune)
    localparam [7:0] VF_VARIABILITY = 8'd40;      // max-min > this => high variability
    localparam [7:0] VF_RATE_THRESHOLD = 8'd60;   // average RR less than this => fast overall
    localparam integer VT_CONSEC_COUNT = 4;       // number of consecutive short intervals to declare VT

    // Internal signals
    reg swr_reg;
    reg sig_reg, sig_reg_d1;
    reg wr_reg;
    wire sig_posedge;

    assign sig_posedge = sig_reg & ~sig_reg_d1;

    // synchronize inputs
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            swr_reg <= 1'b0;
            sig_reg <= 1'b0;
            sig_reg_d1 <= 1'b0;
            wr_reg <= 1'b0;
        end else begin
            swr_reg <= SWr;
            sig_reg <= Sig;
            sig_reg_d1 <= sig_reg;
            wr_reg <= Wr;
        end
    end

    // Interval counter / capture (same idea as your original)
    reg [7:0] interval_counter;
    reg [7:0] captured_interval;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            interval_counter <= 8'b0;
            captured_interval <= 8'b0;
        end else begin
            if (sig_posedge) begin
                captured_interval <= interval_counter;
                interval_counter <= 8'b1; // start counting from 1 after an R-peak
            end else begin
                interval_counter <= interval_counter + 1'b1;
            end
        end
    end

    // Keep an 8-entry sliding window of last RR intervals
    reg [7:0] rr_window [0:WINDOW_SIZE-1];
    integer i;
    // index used only for shifts
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < WINDOW_SIZE; i = i + 1) rr_window[i] <= 8'b0;
        end else if (sig_posedge) begin
            // shift right and insert new interval at [0]
            for (i = WINDOW_SIZE-1; i > 0; i = i - 1) begin
                rr_window[i] <= rr_window[i-1];
            end
            rr_window[0] <= captured_interval;
        end
    end

    // VT detection: count consecutive short intervals
    reg [7:0] consec_short;
    reg vt_flag;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            consec_short <= 8'b0;
            vt_flag <= 1'b0;
        end else if (sig_posedge) begin
            if (captured_interval < VT_THRESHOLD) begin
                consec_short <= consec_short + 1'b1;
            end else begin
                consec_short <= 8'b0;
            end

            if (consec_short + 1 >= VT_CONSEC_COUNT && captured_interval < VT_THRESHOLD) begin
                // +1 because consec_short hasn't counted the current interval yet in this cycle
                vt_flag <= 1'b1;
            end else begin
                // to avoid latching VT forever you can require explicit reset or a timeout;
                // here we clear VT if we see a non-short interval (you can change policy)
                if (captured_interval >= VT_THRESHOLD)
                    vt_flag <= 1'b0;
            end
        end
    end

    // VF detection: compute max, min and average across window and check variability + rate
    reg [7:0] max_rr, min_rr;
    reg [15:0] sum_rr; // to hold sum of 8 * 8-bit = up to 2040 (< 16 bits)
    reg vf_flag;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            max_rr <= 8'd0;
            min_rr <= 8'd255;
            sum_rr <= 16'd0;
            vf_flag <= 1'b0;
        end else if (sig_posedge) begin
            // compute max/min/sum over current window
            max_rr <= rr_window[0];
            min_rr <= rr_window[0];
            sum_rr <= 16'd0;
            for (i = 0; i < WINDOW_SIZE; i = i + 1) begin
                if (rr_window[i] > max_rr) max_rr <= rr_window[i];
                if (rr_window[i] < min_rr) min_rr <= rr_window[i];
                sum_rr <= sum_rr + rr_window[i];
            end

            // calculate average (integer)
            // small divide by WINDOW_SIZE (8) via shift
            // avg = sum_rr >> 3
            if ((max_rr - min_rr) > VF_VARIABILITY) begin
                if ((sum_rr >> 3) < VF_RATE_THRESHOLD) begin
                    vf_flag <= 1'b1;
                end else begin
                    vf_flag <= 1'b0;
                end
            end else begin
                vf_flag <= 1'b0;
            end
        end
    end

    // Keep previous "HIGH/NORMAL/LOW" classification (for compatibility)
    reg [7:0] max_reg;
    reg [7:0] high_out, normal_out, low_out;
    localparam [7:0] INIT_MAX = 8'd1;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            max_reg <= INIT_MAX;
            high_out <= 8'b0;
            normal_out <= 8'b0;
            low_out <= 8'b0;
        end else begin
            // update max_reg on writes as before (simple policy)
            if (wr_reg && captured_interval > max_reg) max_reg <= captured_interval;

            // classify on each R-peak (simple thresholds like before)
            if (sig_posedge && captured_interval > 0) begin
                if (captured_interval >= (max_reg - (max_reg >> 2))) begin
                    high_out <= captured_interval;
                    normal_out <= 8'b0;
                    low_out <= 8'b0;
                end else if (captured_interval > (max_reg >> 2)) begin
                    high_out <= 8'b0;
                    normal_out <= captured_interval;
                    low_out <= 8'b0;
                end else begin
                    high_out <= 8'b0;
                    normal_out <= 8'b0;
                    low_out <= captured_interval;
                end
            end
        end
    end

    // keep wr_reg definition (synchronized) - from earlier
    // wr_reg is updated above in input synchronization block

    // Output assignment
    assign RR_int_ms = captured_interval;
    assign HIGH = high_out;
    assign NORMAL = normal_out;
    assign LOW = low_out;
    assign VT = vt_flag;
    assign VF = vf_flag;

endmodule
