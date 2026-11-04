# Uart_Demo

Xilinx Zynq-7030 (`xc7z030ffg676-2`) 上的 **UART 收发测试模块**，纯 RTL 实现，不依赖任何 Xilinx IP。
用于快速验证板卡串口（TX/RX）是否正常：回环、自动发包、报文、十六进制回显四种模式。

- 工具版本：Vivado 2019.2
- 输入时钟：**40 MHz**
- 波特率：**115200, 8N1**（无校验、1 停止位）
- 语言：Verilog-2001

## 模块结构

| 文件 | 说明 |
|---|---|
| `project_1.srcs/sources_1/new/uart_rx.v` | 接收器。16 倍过采样，在起始位中心复检剔除毛刺，检测停止位错误；输入经两级同步 |
| `project_1.srcs/sources_1/new/uart_tx.v` | 发送器。8N1，`tx_start` / `tx_busy` / `tx_done` 握手 |
| `project_1.srcs/sources_1/new/uart_fifo.v` | 16×8 同步 FIFO，组合读（`empty=0` 当拍即可取数），避免发送忙时丢字节 |
| `project_1.srcs/sources_1/new/uart_test_top.v` | 测试顶层，四种模式 + 4 个状态灯 |
| `project_1.srcs/sim_1/new/tb_uart_test.v` | 自检 testbench，4 种模式全回归 |
| `project_1.srcs/constrs_1/new/uart_test_top.xdc` | 时钟约束 + 引脚模板（**引脚需按板卡原理图填写**） |

数据通路：

```
uart_rx ──> 报文组装（按模式） ──> uart_fifo ──> uart_tx
```

## 四种模式

模式由顶层参数 `MODE` 在**综合前**选定（板上没有拨码开关时用这种方式最省事）：

```verilog
parameter [1:0] MODE = 2'b11   // 2'b00 ECHO / 2'b01 PATTERN / 2'b10 BANNER / 2'b11 HEXECHO
```

| `MODE` | 模式 | 串口助手上看到 | 用途 |
|---|---|---|---|
| `2'b00` | ECHO | 输入什么就回什么 | 双向链路一次验证 |
| `2'b01` | PATTERN | ` !"#$%&'...~` 递增循环（每 `GAP_MS` 一个字符） | 验证发送；示波器可直接量位宽与波特率 |
| `2'b10` | BANNER | 每 `GAP_MS` 打印一行 `UART TEST OK` | 只验证发送 |
| `2'b11` | HEXECHO | 发 `<` → 回 `RX=3C '<'` | 专门验证接收，误码/错位一眼看出 |

HEXECHO 回包共 11 字节：`R X = 高nibble 低nibble 空格 ' 字符 ' CR LF`。
字符若不可打印（`< 0x20` 或 `0x7F`）则显示为 `.`，避免控制字符破坏终端显示，
例如发送 `0x0A` 回 `RX=0A '.'`。

## 参数

```verilog
CLK_FREQ  = 40_000_000   // 必须等于 clk 端口实际频率，否则波特率整体偏移
BAUD_RATE = 115_200
GAP_MS    = 200          // 自动发送间隔 (ms)
FIFO_AW   = 4            // 发送缓冲深度 = 2^FIFO_AW
MODE      = 2'b11
```

分频计算：`BAUD_DIV = CLK_FREQ / BAUD_RATE`，40 MHz / 115200 → 347（实际波特率 115274，误差 −0.06%）。
要求 `CLK_FREQ / BAUD_RATE >= 16`，否则 16 倍过采样失效。

## 状态灯

| LED | 含义 |
|---|---|
| `led[0]` | 收到数据（亮约 50 ms） |
| `led[1]` | 正在发送（亮约 50 ms） |
| `led[2]` | 错误锁存：帧错误或 FIFO 溢出（复位清除） |
| `led[3]` | 心跳，0.5 s 翻转一次，证明时钟/复位正常 |

## 使用方法

1. Vivado 2019.2 打开 `project_1.xpr`；
2. 按板卡原理图修改 `project_1.srcs/constrs_1/new/uart_test_top.xdc` 里的 `PACKAGE_PIN` 与 `IOSTANDARD`
   （**电平必须与 bank 供电一致**，把 1.8 V bank 写成 `LVCMOS33` 可能损伤器件）；
3. 综合 → 实现 → 生成比特流 → 下载；
4. 串口助手设为 **115200 / 8 数据位 / 无校验 / 1 停止位 / 无流控**；
5. 接线：FPGA `uart_tx_pin` 接 USB-UART 的 **RXD**，`uart_rx_pin` 接其 **TXD**（交叉），务必共地。

例：PC 发送 `<`（0x3C），应收到 `RX=3C '<'`。

## 仿真

```tcl
launch_simulation    # top = tb_uart_test
run all
```

`tb_uart_test` 为 4 种模式各实例化一个 DUT（模式是编译期参数，无法运行时切换），
用 `sel` 选择当前被测对象，逐字节比对回包。40 MHz / 115200 下约 12 ms 仿真时间，
XSim 十几秒跑完，预期结果：

```
===== TEST 1 : ECHO (MODE=2'b00) =====
[ OK ] ECHO : 55 'U' ... ff '.'
===== TEST 2 : HEXECHO (MODE=2'b11) =====
[ OK ] HEXECHO '<' : 3c '<'
===== TEST 3 : BANNER (MODE=2'b10) =====
[ OK ] BANNER 'O' : 4f 'O'
===== TEST 4 : PATTERN (MODE=2'b01) =====
[ OK ] PATTERN 递增 : 22 -> 23 -> 24
===== ALL TESTS PASSED =====
```

## 注意

- 源码文件为 **GBK + CRLF** 编码（Vivado 2019.2 在中文 Windows 下默认按 GBK 读取），
  直接在 GitHub 网页上查看中文注释会显示为乱码，本地 Vivado 编辑正常。
- 仓库只提交工程文件与源码；`project_1.runs/`、`project_1.cache/` 等生成目录已在
  `.gitignore` 中排除，克隆后重新综合即可。
- `uart_Demo.v` 是建工程时自动生成的空壳顶层，已被 `uart_test_top` 取代，可忽略。
