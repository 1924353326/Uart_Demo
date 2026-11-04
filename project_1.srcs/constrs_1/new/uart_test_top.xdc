###################################################################################
# uart_test_top 约束模板（xc7z030ffg676-2）
#
#  ★★★ 引脚必须按你板子原理图改！下面 PACKAGE_PIN 全部是占位值 ★★★
#  用哪个 bank、什么电平（LVCMOS33 / LVCMOS18）取决于原理图，填错会不工作，
#  若接到 1.8V bank 却写 LVCMOS33 还可能损伤器件，务必先核对。
#
#  选引脚原则：
#    - clk / rst_n / mode_sel 用普通用户 IO 或拨码；
#    - uart_rx_pin 接 USB-UART 模块的 TXD，uart_tx_pin 接其 RXD（交叉！）；
#    - 不要占用配置 flash、DDR、PS MIO 相关 bank 的专用脚。
###################################################################################

#--------------------------------------------------------------------------
# Bank 电压（按板子实际供电改，1.8V bank 就写 1.8）
#--------------------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

#--------------------------------------------------------------------------
# 主时钟：40 MHz -> 25.000 ns
#--------------------------------------------------------------------------
create_clock -period 25.000 -name sys_clk -waveform {0.000 12.500} [get_ports clk]

#--------------------------------------------------------------------------
# 异步输入不做时序分析
#   uart_rx_pin 已在 RTL 内做两级同步；
#   mode_sel / rst_n 是慢速人工输入
#--------------------------------------------------------------------------
#set_false_path -from [get_ports uart_rx_pin]
#set_false_path -from [get_ports rst_n]
#set_false_path -from [get_ports {mode_sel[*]}]

#--------------------------------------------------------------------------
# 引脚分配（把每行前面的 # 去掉后填真实引脚）
#
#   示例（假设）：
#     set_property -dict {PACKAGE_PIN Y16 IOSTANDARD LVCMOS33} [get_ports clk]
#--------------------------------------------------------------------------
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33} [get_ports clk]
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33} [get_ports rst_n]
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33} [get_ports uart_rx_pin]
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33} [get_ports uart_tx_pin]
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33} [get_ports {mode_sel[0]}]
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33} [get_ports {mode_sel[1]}]
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33} [get_ports {led[0]}]
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33} [get_ports {led[1]}]
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33} [get_ports {led[2]}]
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33} [get_ports {led[3]}]

#--------------------------------------------------------------------------
# 若暂时没有 led / mode_sel 可用，可先用常量顶替（放到单独的 xdc 里）
#   set_property PACKAGE_PIN ... 不填的话会随机布到空闲 IO
#--------------------------------------------------------------------------

set_property PACKAGE_PIN AB19 [get_ports {led[0]}]
set_property PACKAGE_PIN AA18 [get_ports {led[1]}]
set_property PACKAGE_PIN Y18 [get_ports {led[2]}]
set_property PACKAGE_PIN W18 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]
set_property PACKAGE_PIN AC23 [get_ports clk]
set_property PACKAGE_PIN L8 [get_ports rst_n]
set_property PACKAGE_PIN F9 [get_ports uart_rx_pin]
set_property PACKAGE_PIN E8 [get_ports uart_tx_pin]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property IOSTANDARD LVCMOS18 [get_ports rst_n]
set_property IOSTANDARD LVCMOS18 [get_ports uart_rx_pin]
set_property IOSTANDARD LVCMOS18 [get_ports uart_tx_pin]
