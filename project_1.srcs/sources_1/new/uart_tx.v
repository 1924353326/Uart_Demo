`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : uart_tx
// Description : UART 发送器
//   Frame format : 1 start(0) + 8 data(LSB first) + 1 stop(1)，无校验
//   每 bit 保持 BAUD_DIV 个 clk
//
//   握手：tx_start 单周期脉冲 + tx_data 有效 -> tx_busy 拉高 -> 帧末 tx_done 单周期脉冲
//   tx_busy 期间 tx_start 被忽略（使用方需自行排空）
//////////////////////////////////////////////////////////////////////////////////

module uart_tx #(
    parameter integer CLK_FREQ  = 40_000_000,
    parameter integer BAUD_RATE = 115_200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output reg        tx,        // 串口输出（空闲为 1）
    output reg        tx_busy,
    output reg        tx_done     // 单周期脉冲：整帧发完
);

    localparam integer BAUD_DIV = (CLK_FREQ + BAUD_RATE / 2) / BAUD_RATE;
    localparam integer DIVW     = (BAUD_DIV < 2) ? 1 : $clog2(BAUD_DIV);

    reg [DIVW-1:0] div_cnt;
    reg [3:0]      bit_idx;
    reg [9:0]      shreg;      // {stop, data[7:0], start}

    always @(posedge clk) begin
        if (!rst_n) begin
            div_cnt <= {DIVW{1'b0}};
            bit_idx <= 4'd0;
            shreg   <= 10'h3FF;
            tx_busy <= 1'b0;
            tx_done <= 1'b0;
            tx      <= 1'b1;
        end else begin
            tx_done <= 1'b0;

            if (!tx_busy) begin
                tx <= 1'b1;                     // 空闲保持高
                if (tx_start) begin
                    shreg   <= {1'b1, tx_data, 1'b0};
                    tx      <= 1'b0;            // 立即输出起始位
                    tx_busy <= 1'b1;
                    div_cnt <= {DIVW{1'b0}};
                    bit_idx <= 4'd0;
                end
            end else begin
                if (div_cnt == BAUD_DIV - 1) begin
                    div_cnt <= {DIVW{1'b0}};
                    if (bit_idx == 4'd9) begin
                        tx_busy <= 1'b0;
                        tx_done <= 1'b1;
                        tx      <= 1'b1;
                    end else begin
                        bit_idx <= bit_idx + 1'b1;
                        shreg   <= {1'b1, shreg[9:1]};
                        tx      <= shreg[1];
                    end
                end else begin
                    div_cnt <= div_cnt + 1'b1;
                end
            end
        end
    end

endmodule
