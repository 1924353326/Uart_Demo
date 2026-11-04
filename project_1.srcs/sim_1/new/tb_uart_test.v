`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : tb_uart_test
// Description : uart_test_top 自测 testbench
//
//   顶层已经没有 mode_sel 端口（模式改由 parameter MODE 编译期固定），
//   所以这里给 4 个模式各实例化一个 DUT，用 sel 选择"当前被测"的那一个：
//     sel=0 -> ECHO      sel=1 -> PATTERN
//     sel=2 -> BANNER    sel=3 -> HEXECHO
//   未选中的 DUT 其 rx 被拉高（空闲），tx 不被观察，互不干扰。
//
//   测试项：
//     1) ECHO    : 5 个字节（含 0x00/0xFF 边界）原样回显
//     2) HEXECHO : 发 '<'(0x3C) -> "RX=3C '<'\r\n"
//                  发 0x0A(LF) -> "RX=0A '.'\r\n"（不可打印字符显示为 '.'）
//     3) BANNER  : "UART TEST OK\r\n"（先对齐到报文头 'U'）
//     4) PATTERN : 字符递增 0x20 -> 0x21 -> 0x22
//
//   真实 40 MHz / 115200，仿真约 12 ms，XSim 十几秒跑完。
//////////////////////////////////////////////////////////////////////////////////

module tb_uart_test;

    localparam integer CLK_FREQ  = 40_000_000;
    localparam integer BAUD_RATE = 115_200;
    localparam real    BIT_NS    = 1.0e9 / BAUD_RATE;   // 8680.55 ns

    //--------------------------------------------------------------------------
    // 时钟 / 复位
    //--------------------------------------------------------------------------
    reg clk = 1'b0;
    always #12.5 clk = ~clk;                 // 40 MHz -> 25 ns

    reg  rst_n     = 1'b0;
    reg  uart_rx_i = 1'b1;
    reg  [1:0] sel = 2'd0;                   // 当前被测 DUT

    wire [3:0] led_echo, led_pat, led_banner, led_hex;
    wire       tx_echo, tx_pat, tx_banner, tx_hex;

    // 只有被选中的 DUT 能看到 uart_rx_i，其余保持空闲高
    wire rx_echo   = (sel == 2'd0) ? uart_rx_i : 1'b1;
    wire rx_pat    = (sel == 2'd1) ? uart_rx_i : 1'b1;
    wire rx_banner = (sel == 2'd2) ? uart_rx_i : 1'b1;
    wire rx_hex    = (sel == 2'd3) ? uart_rx_i : 1'b1;

    // 接收端观察被选中 DUT 的 TX
    wire uart_tx_o = (sel == 2'd0) ? tx_echo   :
                     (sel == 2'd1) ? tx_pat    :
                     (sel == 2'd2) ? tx_banner : tx_hex;

    //--------------------------------------------------------------------------
    // 4 个模式的 DUT（模式是 parameter，一个实例只能一种）
    //--------------------------------------------------------------------------
    uart_test_top #(
        .CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE),
        .GAP_MS(2), .FIFO_AW(4), .MODE(2'b00)
    ) dut_echo (
        .clk(clk), .rst_n(rst_n), .uart_rx_pin(rx_echo),
        .uart_tx_pin(tx_echo), .led(led_echo)
    );

    uart_test_top #(
        .CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE),
        .GAP_MS(2), .FIFO_AW(4), .MODE(2'b01)
    ) dut_pat (
        .clk(clk), .rst_n(rst_n), .uart_rx_pin(rx_pat),
        .uart_tx_pin(tx_pat), .led(led_pat)
    );

    uart_test_top #(
        .CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE),
        .GAP_MS(2), .FIFO_AW(4), .MODE(2'b10)
    ) dut_banner (
        .clk(clk), .rst_n(rst_n), .uart_rx_pin(rx_banner),
        .uart_tx_pin(tx_banner), .led(led_banner)
    );

    uart_test_top #(
        .CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE),
        .GAP_MS(2), .FIFO_AW(4), .MODE(2'b11)
    ) dut_hex (
        .clk(clk), .rst_n(rst_n), .uart_rx_pin(rx_hex),
        .uart_tx_pin(tx_hex), .led(led_hex)
    );

    //--------------------------------------------------------------------------
    // 统计
    //--------------------------------------------------------------------------
    integer    errors = 0;
    reg  [7:0] got;

    //--------------------------------------------------------------------------
    // 发送 1 字节到 DUT（115200, 8N1）
    //--------------------------------------------------------------------------
    task uart_send;
        input [7:0] d;
        integer i;
        begin
            uart_rx_i = 1'b0;                 // start
            #(BIT_NS);
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx_i = d[i];             // LSB first
                #(BIT_NS);
            end
            uart_rx_i = 1'b1;                 // stop
            #(BIT_NS);
        end
    endtask

    //--------------------------------------------------------------------------
    // 从当前被测 DUT 接收 1 字节
    //--------------------------------------------------------------------------
    task uart_recv;
        output [7:0] d;
        integer i;
        begin
            @(negedge uart_tx_o);             // 等起始位
            #(BIT_NS * 1.5);                  // 对齐到 bit0 中心
            for (i = 0; i < 8; i = i + 1) begin
                d[i] = uart_tx_o;
                #(BIT_NS);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // 收 1 字节并比对（打印时不可打印字符统一显示为 '.'）
    //--------------------------------------------------------------------------
    task check_byte;
        input [7:0]      exp;
        input [8*16-1:0] tag;
        reg   [7:0]      dc;
        begin
            uart_recv(got);
            dc = ((got >= 8'h20) && (got <= 8'h7E)) ? got : 8'h2E;
            if (got !== exp) begin
                $display("[FAIL] %0s : expect %02h, got %02h  (@%0t ns)", tag, exp, got, $time);
                errors = errors + 1;
            end else begin
                $display("[ OK ] %0s : %02h '%c'", tag, got, dc);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // 等当前被测 DUT 的 TX 完全空闲（报文组装空闲 + FIFO 空 + 当前帧发完）
    //--------------------------------------------------------------------------
    task wait_tx_idle;
        begin
            case (sel)
                2'd0: begin
                    wait (dut_echo.ps == 2'd0);
                    wait (dut_echo.txq_empty == 1'b1);
                    wait (dut_echo.u_tx.tx_busy == 1'b0);
                end
                2'd1: begin
                    wait (dut_pat.ps == 2'd0);
                    wait (dut_pat.txq_empty == 1'b1);
                    wait (dut_pat.u_tx.tx_busy == 1'b0);
                end
                2'd2: begin
                    wait (dut_banner.ps == 2'd0);
                    wait (dut_banner.txq_empty == 1'b1);
                    wait (dut_banner.u_tx.tx_busy == 1'b0);
                end
                default: begin
                    wait (dut_hex.ps == 2'd0);
                    wait (dut_hex.txq_empty == 1'b1);
                    wait (dut_hex.u_tx.tx_busy == 1'b0);
                end
            endcase
            repeat (4) @(posedge clk);
        end
    endtask

    //--------------------------------------------------------------------------
    // 对齐到 BANNER 报文头 'U'（BANNER 自由运行，起始相位不定）
    //--------------------------------------------------------------------------
    task wait_banner_head;
        begin
            uart_recv(got);
            while (got !== 8'h55) uart_recv(got);
        end
    endtask

    //--------------------------------------------------------------------------
    // 主激励
    //--------------------------------------------------------------------------
    reg [7:0] vec [0:4];
    reg [7:0] hex_exp [0:10];        // HEXECHO 期望的 11 字节回包
    reg [7:0] p0, p1, p2;

    initial begin
        rst_n = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        //================================================================ ECHO
        $display("\n===== TEST 1 : ECHO (MODE=2'b00) =====");
        sel = 2'd0;
        repeat (10) @(posedge clk);

        vec[0] = 8'h55;
        vec[1] = 8'hA5;
        vec[2] = 8'h00;
        vec[3] = 8'hFF;
        vec[4] = 8'h7E;

        fork
            begin : ECHO_SEND
                integer si;
                for (si = 0; si < 5; si = si + 1) uart_send(vec[si]);
            end
            begin : ECHO_RECV
                integer ri;
                for (ri = 0; ri < 5; ri = ri + 1) check_byte(vec[ri], "ECHO");
            end
        join

        wait_tx_idle;

        //============================================================= HEXECHO
        $display("\n===== TEST 2 : HEXECHO (MODE=2'b11) =====");
        sel = 2'd3;
        repeat (10) @(posedge clk);

        // 回包格式 : R X = hh ' c ' CR LF   （共 11 字节）
        // 第 1 组：发 '<' (0x3C)，可打印 -> 原样显示
        hex_exp[0]  = 8'h52;                       // 'R'
        hex_exp[1]  = 8'h58;                       // 'X'
        hex_exp[2]  = 8'h3D;                       // '='
        hex_exp[3]  = 8'h33;                       // '3'
        hex_exp[4]  = 8'h43;                       // 'C'
        hex_exp[5]  = 8'h20;                       // ' '
        hex_exp[6]  = 8'h27;                       // '''
        hex_exp[7]  = 8'h3C;                       // '<'
        hex_exp[8]  = 8'h27;                       // '''
        hex_exp[9]  = 8'h0D;                       // CR
        hex_exp[10] = 8'h0A;                       // LF

        fork
            begin : HEX_SEND1
                uart_send(8'h3C);
            end
            begin : HEX_RECV1
                integer ri;
                for (ri = 0; ri < 11; ri = ri + 1) check_byte(hex_exp[ri], "HEXECHO '<'");
            end
        join

        wait_tx_idle;

        // 第 2 组：发 0x0A (LF)，不可打印 -> 显示为 '.'
        hex_exp[3] = 8'h30;                        // '0'
        hex_exp[4] = 8'h41;                        // 'A'
        hex_exp[7] = 8'h2E;                        // '.'

        fork
            begin : HEX_SEND2
                uart_send(8'h0A);
            end
            begin : HEX_RECV2
                integer ri;
                for (ri = 0; ri < 11; ri = ri + 1) check_byte(hex_exp[ri], "HEXECHO LF ");
            end
        join

        wait_tx_idle;

        //============================================================== BANNER
        $display("\n===== TEST 3 : BANNER (MODE=2'b10) =====");
        sel = 2'd2;
        repeat (10) @(posedge clk);

        wait_banner_head;                          // 已收到 'U'
        $display("[ OK ] BANNER 'U' : 55 'U'");
        check_byte(8'h41, "BANNER 'A'");
        check_byte(8'h52, "BANNER 'R'");
        check_byte(8'h54, "BANNER 'T'");
        check_byte(8'h20, "BANNER ' '");
        check_byte(8'h54, "BANNER 'T'");
        check_byte(8'h45, "BANNER 'E'");
        check_byte(8'h53, "BANNER 'S'");
        check_byte(8'h54, "BANNER 'T'");
        check_byte(8'h20, "BANNER ' '");
        check_byte(8'h4F, "BANNER 'O'");
        check_byte(8'h4B, "BANNER 'K'");
        check_byte(8'h0D, "BANNER CR");
        check_byte(8'h0A, "BANNER LF");

        //============================================================= PATTERN
        $display("\n===== TEST 4 : PATTERN (MODE=2'b01) =====");
        sel = 2'd1;
        repeat (10) @(posedge clk);

        uart_recv(p0);
        uart_recv(p1);
        uart_recv(p2);

        if ((p1 == (p0 + 8'd1)) && (p2 == (p1 + 8'd1))) begin
            $display("[ OK ] PATTERN 递增 : %02h -> %02h -> %02h", p0, p1, p2);
        end else begin
            $display("[FAIL] PATTERN 非递增 : %02h -> %02h -> %02h", p0, p1, p2);
            errors = errors + 1;
        end
        if ((p0 < 8'h20) || (p0 > 8'h7E)) begin
            $display("[FAIL] PATTERN 超出可打印范围 : %02h", p0);
            errors = errors + 1;
        end

        //=============================================================== 汇总
        $display("\n==============================================");
        if (errors == 0) $display("===== ALL TESTS PASSED =====");
        else             $display("===== %0d ERROR(S) =====", errors);
        $display("==============================================\n");
        $finish;
    end

    //--------------------------------------------------------------------------
    // 看门狗
    //--------------------------------------------------------------------------
    initial begin
        #40_000_000;                             // 40 ms 上限
        $display("[FAIL] simulation timeout (watchdog)");
        $display("===== %0d ERROR(S) =====", errors + 1);
        $finish;
    end

endmodule
