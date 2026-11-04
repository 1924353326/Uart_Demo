`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : uart_fifo
// Description : 同步 FIFO（单时钟，组合读，深度 2^AW）
//   用于把待发字节排队，避免发送忙时丢字节。
//   dout 为组合输出（mem[rp]），empty=0 的当拍即可取数；rd_en 与取数同拍即可。
//////////////////////////////////////////////////////////////////////////////////

module uart_fifo #(
    parameter integer DW = 8,
    parameter integer AW = 4
)(
    input  wire          clk,
    input  wire          rst_n,
    input  wire          wr_en,
    input  wire [DW-1:0] din,
    input  wire          rd_en,
    output wire [DW-1:0] dout,
    output wire          full,
    output wire          empty,
    output wire [AW:0]   count
);

    localparam integer DEPTH = (1 << AW);

    reg [DW-1:0] mem [0:DEPTH-1];
    reg [AW-1:0] wp;
    reg [AW-1:0] rp;
    reg [AW:0]   cnt;

    wire do_wr = wr_en && !full;
    wire do_rd = rd_en && !empty;

    assign dout  = mem[rp];
    assign full  = (cnt == DEPTH);
    assign empty = (cnt == {(AW+1){1'b0}});
    assign count = cnt;

    always @(posedge clk) begin
        if (!rst_n) begin
            wp  <= {AW{1'b0}};
            rp  <= {AW{1'b0}};
            cnt <= {(AW+1){1'b0}};
        end else begin
            if (do_wr) begin
                mem[wp] <= din;
                wp      <= wp + 1'b1;
            end
            if (do_rd) begin
                rp <= rp + 1'b1;
            end
            if (do_wr && !do_rd)      cnt <= cnt + 1'b1;
            else if (!do_wr && do_rd) cnt <= cnt - 1'b1;
        end
    end

endmodule
