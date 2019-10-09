module top;

    task skip1;
        $display("HELLO skip1");
        return;
        $display("UNREACHABLE");
    endtask
    function void skip2;
        $display("HELLO skip2");
        return;
        $display("UNREACHABLE");
    endfunction
    function int skip3;
        $display("HELLO skip3");
        return 1;
        $display("UNREACHABLE");
    endfunction
    task skip4;
        for (int i = 0; i < 10; ++i) begin
            $display("HELLO skip4");
            return;
            $display("UNREACHABLE");
        end
        $display("UNREACHABLE");
    endtask
    task skip5;
        for (int i = 0; i < 10; ++i) begin
            $display("HELLO skip5-1");
            for (int j = 0; j < 10; ++j) begin
                $display("HELLO skip5-2");
                return;
                $display("UNREACHABLE");
            end
            $display("UNREACHABLE");
        end
        $display("UNREACHABLE");
    endtask
    initial begin
        skip1;
        skip2;
        $display(skip3());
        skip4;
        skip5;
    end

    initial
        for (int i = 0; i < 10; ++i) begin
            $display("Loop Y:", i);
            continue;
            $display("UNREACHABLE");
        end

    initial
        for (int i = 0; i < 10; ++i) begin
            $display("Loop Z:", i);
            break;
            $display("UNREACHABLE");
        end

    initial
        for (int i = 0; i < 10; ++i)
            if (i < 5)
                $display("Loop A:", i);
            else
                break;

    initial
        for (int i = 0; i < 10; ++i) begin
            if (i < 3)
                $display("Loop B-1:", i);
            else if (i < 7)
                $display("Loop B-2:", i);
            else begin
                $display("Loop B-3:", i);
                continue;
                $display("UNREACHABLE");
            end
            $display("Loop B:", i);
        end

endmodule
