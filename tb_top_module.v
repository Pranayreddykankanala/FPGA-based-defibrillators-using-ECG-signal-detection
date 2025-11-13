`timescale 1ns / 1ps
module tb_top_module();

    reg clk;
    reg rst;
    reg SWr;
    reg Sig;
    reg Wr;
    wire [7:0] RR_int_ms;
    wire [7:0] HIGH;
    wire [7:0] NORMAL;
    wire [7:0] LOW;
    wire VT;
    wire VF;

    top_module uut (
        .clk(clk),
        .rst(rst),
        .SWr(SWr),
        .Sig(Sig),
        .Wr(Wr),
        .RR_int_ms(RR_int_ms),
        .HIGH(HIGH),
        .NORMAL(NORMAL),
        .LOW(LOW),
        .VT(VT),
        .VF(VF)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz clock
    end

    initial begin
        // initialize
        rst = 1;
        SWr = 0;
        Wr = 0;
        Sig = 0;

        $display("time\trst\tSWr\tWr\tSig\tRR\tVT\tVF\tHIGH\tNORMAL\tLOW");
        #100;
        rst = 0;
        #20;

        // --- Normal rhythm: moderate intervals (should not trigger VT/VF) ---
        $display("\n-- Normal rhythm --");
        SWr = 1; Wr = 1;
        repeat (8) begin
            Sig = 1; #20; Sig = 0; #80; // interval ~80
        end
        #200;

        // --- VT: repeated short intervals -> trigger VT ---
        $display("\n-- VT sequence: repeated short intervals (should set VT) --");
        repeat (6) begin
            Sig = 1; #20; Sig = 0; #30; // short interval ~30 (below VT_THRESHOLD)
        end
        #200;

        // Pause
        #200;

        // --- VF: irregular chaotic short intervals -> trigger VF ---
        $display("\n-- VF sequence: highly variable & fast (should set VF) --");
        // push a set of 8 variable fast intervals
        Sig = 1; #20; Sig = 0; #25;  // 25
        Sig = 1; #20; Sig = 0; #40;  // 40
        Sig = 1; #20; Sig = 0; #15;  // 15
        Sig = 1; #20; Sig = 0; #60;  // 60
        Sig = 1; #20; Sig = 0; #30;  // 30
        Sig = 1; #20; Sig = 0; #20;  // 20
        Sig = 1; #20; Sig = 0; #55;  // 55
        Sig = 1; #20; Sig = 0; #10;  // 10
        #200;

        // wrap-up
        $display("\n-- End of simulation --");
        #200;
        $finish;
    end

    // Monitor outputs at every R-peak edge (display when things change)
    reg [7:0] prevRR = 0;
    reg prevVT = 0, prevVF = 0;
    always @(posedge clk) begin
        if (!rst) begin
            if (RR_int_ms != prevRR || VT != prevVT || VF != prevVF) begin
                $display("%0t\t%b\t%b\t%b\t%b\t%d\t%b\t%b\t%d\t%d\t%d",
                         $time, rst, SWr, Wr, Sig, RR_int_ms, VT, VF, HIGH, NORMAL, LOW);
                prevRR = RR_int_ms;
                prevVT = VT;
                prevVF = VF;
            end
        end
    end

    initial begin
        $dumpfile("tb_top_module.vcd");
        $dumpvars(0, tb_top_module);
    end

endmodule
