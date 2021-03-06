module top;
    generate
        for (genvar i = 1; i < 5; ++i) begin
            initial begin
                integer x, y;
                x = $unsigned(i'(1'sb1));
                y = $unsigned((i + 5)'(1'sb1));
                $display("%0d %b %b", i, x, y);
            end
            for (genvar j = 3; j < 6; ++j) begin
                initial begin
                    integer x;
                    x = $unsigned((i * j)'(1'sb1));
                    $display("%0d %0d %b", i, j, x);
                end
            end
        end
    endgenerate
endmodule
