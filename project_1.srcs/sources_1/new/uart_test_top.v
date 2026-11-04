`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : uart_test_top
// Description : UART 收发自测顶层（无任何 Xilinx IP 依赖）
//
//   结构：
//     uart_rx ──┐                                  ┌── uart_tx
//               ├─(按 mode 组装应答报文)── uart_fifo ┘
//     模式由 mode_sel 拨码/按键选择（已做两级同步）：
//
//     mode_sel = 2'b00  ECHO     收到什么发什么（双向链路一次性验证，最常用）
//     mode_sel = 2'b01  PATTERN  每隔 GAP_MS 发一个递增 ASCII 0x20~0x7E
//                                -> 终端看到 " !\"#$%&..." 循环，示波器可直接量位宽
//     mode_sel = 2'b10  BANNER   每隔 GAP_MS 发 "UART TEST OK\r\n"
//                                -> 只验证 TX（不看输入）
//     mode_sel = 2'b11  HEXECHO  每收到 1 字节，回 "RX=3C '<'\r\n"
//                                即 十六进制值 + 原字符（不可打印字符显示为 '.'）
//                                -> 专门验证 RX，误码/错位一眼看出
//
//   LED：
//     led[0]  收到数据（亮约 50 ms）
//     led[1]  正在发送（亮约 50 ms）
//     led[2]  错误锁存（帧错误 或 FIFO 溢出；复位清除）
//     led[3]  心跳 0.5 s 翻转（证明时钟/复位正常）
//
//   参数：CLK_FREQ 必须等于 clk 端口实际频率，否则波特率整体偏移
//////////////////////////////////////////////////////////////////////////////////

module uart_test_top #(
    parameter integer CLK_FREQ  = 40_000_000,   // <<< 板载/PS 时钟频率
    parameter integer BAUD_RATE = 115_200,      // 波特率
    parameter integer GAP_MS    = 200,          // 自动发送间隔 (ms)
    parameter integer FIFO_AW   = 4,            // 发送缓冲深度 = 2^FIFO_AW
    // 运行模式（编译期固定）：板上没有拨码开关时用这个参数选模式
    //   2'b00 ECHO / 2'b01 PATTERN / 2'b10 BANNER / 2'b11 HEXECHO
    // 若以后要改成运行时用拨码切换，把下面的 mode_sel 改成 input 端口即可
    parameter [1:0]   MODE      = 2'b11
)(
    input  wire       clk,
    input  wire       rst_n,        // 低有效复位，建议接按键或 PS 复位
    input  wire       uart_rx_pin,  // 串口输入（接 USB-UART 的 TX）
    output wire       uart_tx_pin,  // 串口输出（接 USB-UART 的 RX）
    output reg  [3:0] led
);

    //==========================================================================
    // 参数与常量
    //==========================================================================
    localparam [1:0] M_ECHO    = 2'b00;
    localparam [1:0] M_PATTERN = 2'b01;
    localparam [1:0] M_BANNER  = 2'b10;
    localparam [1:0] M_HEX     = 2'b11;

    localparam integer FIFO_DEPTH = (1 << FIFO_AW);
    localparam integer GAP_CYC    = (CLK_FREQ / 1000) * GAP_MS;
    localparam integer HOLD_CYC   = (CLK_FREQ / 1000) * 50;      // LED 保持 50 ms
    localparam integer HB_CYC     = (CLK_FREQ / 2);              // 心跳 0.5 s

    localparam [3:0] BANNER_LEN = 4'd14;   // "UART TEST OK\r\n"
    localparam [3:0] HEX_LEN    = 4'd11;   // "RX=xx 'c'\r\n"

    //==========================================================================
    // 模式选择同步（拨码开关是异步输入）
    //==========================================================================
    //==========================================================================
    // 模式选择：由 parameter MODE 固定；两级同步保留，方便以后改回端口
    //==========================================================================
    wire [1:0] mode_sel = MODE;

    (* ASYNC_REG = "TRUE" *) reg [1:0] mode_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] mode;
    always @(posedge clk) begin
        if (!rst_n) begin
            mode_meta <= 2'b00;
            mode      <= 2'b00;
        end else begin
            mode_meta <= mode_sel;
            mode      <= mode_meta;
        end
    end

    //==========================================================================
    // RX
    //==========================================================================
    wire [7:0] rx_data;
    wire       rx_valid;
    wire       rx_err;
    wire       rx_busy;

    uart_rx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_rx (
        .clk       (clk),
        .rst_n     (rst_n),
        .rx        (uart_rx_pin),
        .rx_data   (rx_data),
        .rx_valid  (rx_valid),
        .frame_err (rx_err),
        .rx_busy   (rx_busy)
    );

    //==========================================================================
    // 发送缓冲 FIFO
    //==========================================================================
    wire [7:0]       txq_dout;
    wire             txq_full;
    wire             txq_empty;
    wire [FIFO_AW:0] txq_cnt;

    reg              txq_wr;
    reg  [7:0]       txq_wr_data;
    reg              txq_rd;

    uart_fifo #(
        .DW (8),
        .AW (FIFO_AW)
    ) u_txq (
        .clk   (clk),
        .rst_n (rst_n),
        .wr_en (txq_wr),
        .din   (txq_wr_data),
        .rd_en (txq_rd),
        .dout  (txq_dout),
        .full  (txq_full),
        .empty (txq_empty),
        .count (txq_cnt)
    );

    //==========================================================================
    // TX
    //==========================================================================
    reg  [7:0] tx_data;
    reg        tx_start;
    wire       tx_busy;
    wire       tx_done;

    uart_tx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx       (uart_tx_pin),
        .tx_busy  (tx_busy),
        .tx_done  (tx_done)
    );

    // FIFO -> TX 取数：FIFO 非空且发送空闲时取一个字节发起一帧
    always @(posedge clk) begin
        if (!rst_n) begin
            tx_start <= 1'b0;
            tx_data  <= 8'h00;
            txq_rd   <= 1'b0;
        end else begin
            tx_start <= 1'b0;
            txq_rd   <= 1'b0;
            if (!tx_busy && !tx_start && !txq_empty) begin
                tx_data  <= txq_dout;     // 组合读，本拍有效
                tx_start <= 1'b1;
                txq_rd   <= 1'b1;
            end
        end
    end

    //==========================================================================
    // 报文组装：把当前模式要求发送的字节压入 FIFO
    //==========================================================================
    localparam [1:0] PS_IDLE = 2'd0,
                     PS_PUSH = 2'd1;

    reg [1:0]  ps;
    reg [3:0]  p_idx;
    reg [3:0]  p_last;
    reg [7:0]  p_hold;      // HEXECHO 锁存的接收字节
    reg [1:0]  p_msg;       // 锁存的报文类型
    reg [7:0]  pat_byte;
    reg [31:0] gap_cnt;
    reg        drop_flag;   // FIFO 满导致丢弃

    wire gap_hit = (gap_cnt == GAP_CYC - 1);

    //--------------------------------------------------------------------------
    // 自动发送节拍（GAP_MS 一次脉冲）
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n)       gap_cnt <= 32'd0;
        else if (gap_hit) gap_cnt <= 32'd0;
        else              gap_cnt <= gap_cnt + 1'b1;
    end

    //--------------------------------------------------------------------------
    // 报文取字节
    //--------------------------------------------------------------------------
    // 十六进制半字节 -> ASCII
    function [7:0] hex_ascii;
        input [3:0] n;
        begin
            hex_ascii = (n < 4'd10) ? (8'h30 + {4'h0, n})
                                    : (8'h37 + {4'h0, n});   // 'A'..'F'
        end
    endfunction

    // 按 (索引, 锁存字节, 报文类型) 取第 i 个字节
    function [7:0] burst_char;
        input [3:0] i;
        input [7:0] h;
        input [1:0] m;
        begin
            case (m)
                M_BANNER: case (i)
                    4'd0 : burst_char = 8'h55;  // 'U'
                    4'd1 : burst_char = 8'h41;  // 'A'
                    4'd2 : burst_char = 8'h52;  // 'R'
                    4'd3 : burst_char = 8'h54;  // 'T'
                    4'd4 : burst_char = 8'h20;  // ' '
                    4'd5 : burst_char = 8'h54;  // 'T'
                    4'd6 : burst_char = 8'h45;  // 'E'
                    4'd7 : burst_char = 8'h53;  // 'S'
                    4'd8 : burst_char = 8'h54;  // 'T'
                    4'd9 : burst_char = 8'h20;  // ' '
                    4'd10: burst_char = 8'h4F;  // 'O'
                    4'd11: burst_char = 8'h4B;  // 'K'
                    4'd12: burst_char = 8'h0D;  // CR
                    default: burst_char = 8'h0A; // LF
                endcase
                M_HEX: case (i)
                    4'd0 : burst_char = 8'h52;                 // 'R'
                    4'd1 : burst_char = 8'h58;                 // 'X'
                    4'd2 : burst_char = 8'h3D;                 // '='
                    4'd3 : burst_char = hex_ascii(h[7:4]);     // 高半字节
                    4'd4 : burst_char = hex_ascii(h[3:0]);     // 低半字节
                    4'd5 : burst_char = 8'h20;                 // ' '
                    4'd6 : burst_char = 8'h27;                 // '''
                    // 可打印(0x20~0x7E)原样输出，其余(控制符/0x7F)用 '.' 代替
                    4'd7 : burst_char = ((h >= 8'h20) && (h <= 8'h7E)) ? h : 8'h2E;
                    4'd8 : burst_char = 8'h27;                 // '''
                    4'd9 : burst_char = 8'h0D;                 // CR
                    default: burst_char = 8'h0A;               // LF
                endcase
                default: burst_char = 8'h2E;                   // '.'
            endcase
        end
    endfunction

    //--------------------------------------------------------------------------
    // 报文组装状态机
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            ps          <= PS_IDLE;
            p_idx       <= 4'd0;
            p_last      <= 4'd0;
            p_hold      <= 8'h00;
            p_msg       <= 2'b00;
            pat_byte    <= 8'h20;
            txq_wr      <= 1'b0;
            txq_wr_data <= 8'h00;
            drop_flag   <= 1'b0;
        end else begin
            txq_wr <= 1'b0;

            case (ps)
                //--------------------------------------------------------------
                PS_IDLE: begin
                    case (mode)
                        // 回显：收到即入队
                        M_ECHO: begin
                            if (rx_valid) begin
                                if (!txq_full) begin
                                    txq_wr      <= 1'b1;
                                    txq_wr_data <= rx_data;
                                end else begin
                                    drop_flag <= 1'b1;
                                end
                            end
                        end
                        // 递增字符流：每 GAP_MS 一个
                        M_PATTERN: begin
                            if (gap_hit) begin
                                if (!txq_full) begin
                                    txq_wr      <= 1'b1;
                                    txq_wr_data <= pat_byte;
                                    pat_byte    <= (pat_byte == 8'h7E) ? 8'h20
                                                                      : (pat_byte + 1'b1);
                                end
                            end
                        end
                        // 固定报文：整包压入，空间不够就跳过本次
                        M_BANNER: begin
                            if (gap_hit && (txq_cnt <= (FIFO_DEPTH - BANNER_LEN))) begin
                                ps     <= PS_PUSH;
                                p_idx  <= 4'd0;
                                p_last <= BANNER_LEN - 1'b1;
                                p_msg  <= M_BANNER;
                            end
                        end
                        // 十六进制回显：整包压入
                        default: begin
                            if (rx_valid) begin
                                if (txq_cnt <= (FIFO_DEPTH - HEX_LEN)) begin
                                    p_hold <= rx_data;
                                    ps     <= PS_PUSH;
                                    p_idx  <= 4'd0;
                                    p_last <= HEX_LEN - 1'b1;
                                    p_msg  <= M_HEX;
                                end else begin
                                    drop_flag <= 1'b1;
                                end
                            end
                        end
                    endcase
                end
                //--------------------------------------------------------------
                PS_PUSH: begin
                    txq_wr      <= 1'b1;
                    txq_wr_data <= burst_char(p_idx, p_hold, p_msg);
                    if (p_idx == p_last) ps    <= PS_IDLE;
                    else                 p_idx <= p_idx + 1'b1;
                end
                //--------------------------------------------------------------
                default: ps <= PS_IDLE;
            endcase
        end
    end

    //==========================================================================
    // 指示灯
    //==========================================================================
    reg [31:0] rx_hold;
    reg [31:0] tx_hold;
    reg        err_sticky;
    reg [31:0] hb_cnt;
    reg        hb;

    always @(posedge clk) begin
        if (!rst_n) begin
            rx_hold    <= 32'd0;
            tx_hold    <= 32'd0;
            err_sticky <= 1'b0;
            hb_cnt     <= 32'd0;
            hb         <= 1'b0;
            led        <= 4'b0000;
        end else begin
            // RX 活动
            if (rx_valid)                rx_hold <= HOLD_CYC;
            else if (rx_hold != 32'd0)   rx_hold <= rx_hold - 1'b1;

            // TX 活动
            if (tx_start)                tx_hold <= HOLD_CYC;
            else if (tx_hold != 32'd0)   tx_hold <= tx_hold - 1'b1;

            // 错误锁存
            if (rx_err | drop_flag) err_sticky <= 1'b1;

            // 心跳
            if (hb_cnt == HB_CYC - 1) begin
                hb_cnt <= 32'd0;
                hb     <= ~hb;
            end else begin
                hb_cnt <= hb_cnt + 1'b1;
            end

            led[0] <= (rx_hold != 32'd0);
            led[1] <= (tx_hold != 32'd0);
            led[2] <= err_sticky;
            led[3] <= hb;
        end
    end

    // 未使用的状态位（便于仿真观察，综合会被优化掉）
    wire unused = rx_busy ^ tx_done;

endmodule
