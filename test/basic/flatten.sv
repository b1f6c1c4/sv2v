`define CASE(name, dims, a, b) \
module name(clock, in, out); \
    input wire clock, in; \
    output logic dims out; \
    initial out[0+a] = 0; \
    initial out[1+a] = 0; \
    initial out[2+a] = 0; \
    always @(posedge clock) begin \
        /*$display($time, `" name ", out[0+a][1+b+:1]);*/ \
        /*$display($time, `" name ", out[0+a][1+b+:1]);*/ \
        /*$display($time, `" name ", out[1+a][1+b+:1]);*/ \
        /*$display($time, `" name ", out[1+a][1+b+:1]);*/ \
        /*$display($time, `" name ", out[2+a][1+b+:1]);*/ \
        /*$display($time, `" name ", out[2+a][1+b+:1]);*/ \
 \
        out[2+a][4+b] = out[2+a][3+b]; \
        out[2+a][3+b] = out[2+a][2+b]; \
        out[2+a][2+b] = out[2+a][1+b]; \
        out[2+a][1+b] = out[2+a][0+b]; \
        out[2+a][0+b] = out[1+a][4+b]; \
 \
        out[1+a][4+b] = out[1+a][3+b]; \
        out[1+a][3+b] = out[1+a][2+b]; \
        out[1+a][2+b] = out[1+a][1+b]; \
        out[1+a][1+b] = out[1+a][0+b]; \
        out[1+a][0+b] = out[0+a][4+b]; \
 \
        out[0+a][4+b] = out[0+a][3+b]; \
        out[0+a][3+b] = out[0+a][2+b]; \
        out[0+a][2+b] = out[0+a][1+b]; \
        out[0+a][1+b] = out[0+a][0+b]; \
        out[0+a][0+b] = in; \
 \
    end \
endmodule

`CASE(A1, [2:0][4:0], 0, 0)
`CASE(A2, [0:2][0:4], 0, 0)
`CASE(A3, [0:2][4:0], 0, 0)
`CASE(A4, [2:0][0:4], 0, 0)

`CASE(B1, [3:1][5:1], 1, 1)
`CASE(B2, [1:3][1:5], 1, 1)
`CASE(B3, [1:3][5:1], 1, 1)
`CASE(B4, [3:1][1:5], 1, 1)

`CASE(C1, [4:2][6:2], 2, 2)
`CASE(C2, [2:4][2:6], 2, 2)
`CASE(C3, [2:4][6:2], 2, 2)
`CASE(C4, [4:2][2:6], 2, 2)

`CASE(D1, [5:3][6:2], 3, 2)
`CASE(D2, [3:5][2:6], 3, 2)
`CASE(D3, [3:5][6:2], 3, 2)
`CASE(D4, [5:3][2:6], 3, 2)
