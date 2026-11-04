`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : uart_rx
// Description : UART 接收器（16 倍过采样，带起始位毛刺剔除、帧错误检测）
//   Frame format : 1 start(0) + 8 data(LSB first) + 1 stop(1)，无校验
//
//   Clocking :
//     BAUD_DIV = CLK_FREQ / BAUD_RATE        （每个 bit 的时钟数）
//     OS_DIV   = BAUD_DIV / OVERSAMPLE       （每个采样节拍的时钟数）
//     要求 BAUD_DIV >= OVERSAMPLE，否则过采样失效
//       40 MHz / 115200 -> BAUD_DIV=347, OS_DIV=21  OK
//       40 MHz / 9600   -> BAUD_DIV=4166, OS_DIV=260 OK
//
//   Sampling strategy :
//     IDLE  : 检测 rx 同步后为 0（起始位跳变）
//     START : 等 OVERSAMPLE/2 个节拍（=起始位中心）确认仍为 0，否则判毛刺丢弃
//     DATA  : 每 OVERSAMPLE 个节拍在 bit 中心采样 1 位，右移入 shreg
//     STOP  : 停止位中心采样，为 0 则输出 frame_err 脉冲（波特率不匹配/线序错）
//////////////////////////////////////////////////////////////////////////////////

module uart_rx #(
    parameter integer CLK_FREQ   = 40_000_000,
    parameter integer BAUD_RATE  = 115_200,
    parameter integer OVERSAMPLE = 16
)(
    input  wire       clk,
    input  wire       rst_n,      // 低有效复位
    input  wire       rx,         // 原始异步串口输入
    output reg  [7:0] rx_data,    // 收到的字节
    output reg        rx_valid,   // 单周期有效脉冲
    output reg        frame_err,  // 单周期脉冲：停止位错误
    output reg        rx_busy     // 正在收一帧
);

    localparam integer BAUD_DIV = (CLK_FREQ + BAUD_RATE / 2) / BAUD_RATE;
    localparam integer OS_DIV   = (BAUD_DIV < OVERSAMPLE) ? 1 : (BAUD_DIV / OVERSAMPLE);
    localparam integer OSW      = (OS_DIV < 2) ? 1 : $clog2(OS_DIV);
    localparam integer OS_CNT_W = (OVERSAMPLE < 2) ? 1 : $clog2(OVERSAMPLE);

    //--------------------------------------------------------------------------
    // 采样节拍产生：每 OS_DIV 个 clk 产生一个 os_tick
    //--------------------------------------------------------------------------
    reg [OSW-1:0] os_div_cnt;
    wire os_tick = (os_div_cnt == OS_DIV - 1);

    always @(posedge clk) begin
        if (!rst_n)        os_div_cnt <= {OSW{1'b0}};
        else if (os_tick)  os_div_cnt <= {OSW{1'b0}};
        else               os_div_cnt <= os_div_cnt + 1'b1;
    end

    //--------------------------------------------------------------------------
    // 异步输入两级同步
    //--------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg rx_meta;
    (* ASYNC_REG = "TRUE" *) reg rx_sync;

    always @(posedge clk) begin
        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    //--------------------------------------------------------------------------
    // 接收状态机
    //--------------------------------------------------------------------------
    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    reg [1:0]          state;
    reg [OS_CNT_W-1:0] os_cnt;
    reg [2:0]          bit_idx;
    reg [7:0]          shreg;

    always @(posedge clk) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            os_cnt    <= {OS_CNT_W{1'b0}};
            bit_idx   <= 3'd0;
            shreg     <= 8'h00;
            rx_data   <= 8'h00;
            rx_valid  <= 1'b0;
            frame_err <= 1'b0;
            rx_busy   <= 1'b0;
        end else begin
            rx_valid  <= 1'b0;
            frame_err <= 1'b0;

            if (os_tick) begin
                case (state)
                    //----------------------------------------------------------
                    S_IDLE: begin
                        rx_busy <= 1'b0;
                        if (!rx_sync) begin          // 检测到下降沿
                            state  <= S_START;
                            os_cnt <= {OS_CNT_W{1'b0}};
                            rx_busy <= 1'b1;
                        end
                    end
                    //----------------------------------------------------------
                    S_START: begin
                        if (os_cnt == (OVERSAMPLE/2 - 1)) begin
                            if (!rx_sync) begin      // 起始位中心仍为 0 -> 真起始位
                                state   <= S_DATA;
                                os_cnt  <= {OS_CNT_W{1'b0}};
                                bit_idx <= 3'd0;
                            end else begin
                                state   <= S_IDLE;   // 毛刺，丢弃
                            end
                        end else begin
                            os_cnt <= os_cnt + 1'b1;
                        end
                    end
                    //----------------------------------------------------------
                    S_DATA: begin
                        if (os_cnt == (OVERSAMPLE - 1)) begin
                            os_cnt <= {OS_CNT_W{1'b0}};
                            shreg  <= {rx_sync, shreg[7:1]};   // LSB first
                            if (bit_idx == 3'd7) state   <= S_STOP;
                            else                 bit_idx <= bit_idx + 1'b1;
                        end else begin
                            os_cnt <= os_cnt + 1'b1;
                        end
                    end
                    //----------------------------------------------------------
                    S_STOP: begin
                        if (os_cnt == (OVERSAMPLE - 1)) begin
                            os_cnt  <= {OS_CNT_W{1'b0}};
                            state   <= S_IDLE;
                            rx_busy <= 1'b0;
                            if (rx_sync) begin
                                rx_data  <= shreg;
                                rx_valid <= 1'b1;
                            end else begin
                                frame_err <= 1'b1;          // 停止位为 0
                            end
                        end else begin
                            os_cnt <= os_cnt + 1'b1;
                        end
                    end
                    //----------------------------------------------------------
                    default: state <= S_IDLE;
                endcase
            end
        end
    end

endmodule
