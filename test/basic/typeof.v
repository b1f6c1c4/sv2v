module top;
    function f;
        input x;
        begin
            f = 1'b1 ^ x;
            $display("f(%b) called", x);
        end
    endfunction
    task t;
        input x;
        $display("t(%b) called", x);
    endtask

    initial begin : block
        reg x, y;
        x = f(0);
        y = ~x;
        $display("%b", x);
        $display("%b", y);
        $display("%b", 32'd1);
        $display("%b", 32'd1);
        $display("%b", 32'd3);
        x = f(1);
        x = f(0);
        t(1);
    end

    parameter FLAG = 1;
    initial begin : block2
        reg [4:1] x;
        reg [3:0] y;
        reg [4:0] z;
        reg [31:0] a;
        reg [7:0] b;
        reg [3:0] c, d;
        x = 4'b1011;
        y = x ^ 3'b111;
        z = x ^ 5'b11111;
        a = {8 {x}};
        b = {x, y};
        c = FLAG ? x : y;
        d = !FLAG ? x : y;
        $display("%b %d %d", x, 4, 1);
        $display("%b %d %d", y, 3, 0);
        $display("%b %d %d", z, 4, 0);
        $display("%b %d %d", a, 31, 0);
        $display("%b %d %d", b, 7, 0);
        $display("%b %d %d", c, 3, 0);
        $display("%b %d %d", d, 3, 0);
    end

    parameter W = 4;
    initial begin : block3
        reg w;
        reg [W-1:0] x, y, z;
        w = 1;
        x = 4'hA;
        y = FLAG ? x : 4'hF;
        z = !FLAG ? y : 4'hF;
        $display("%b %d %d", w, 0, 0);
        $display("%b %d %d", x, W-1, 0);
        $display("%b %d %d", y, W-1, 0);
        $display("%b %d %d", z, W-1, 0);
    end

    initial begin : block4
        integer w, x, z;
        reg [31:0]  y;
        w = 1;
        x = -1;
        y = 32'hffff_ffff;
        z = 32'shffff_ffff;
        $display("%b %d %d %d", w, w, 31, 0);
        $display("%b %d %d %d", x, x, 31, 0);
        $display("%b %d %d %d", y, y, 31, 0);
        $display("%b %d %d %d", z, z, 31, 0);
    end
endmodule
