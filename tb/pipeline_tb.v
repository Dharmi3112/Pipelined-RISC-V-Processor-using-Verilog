`timescale 1ns/1ps

module tb;

reg clk;
reg rst;

riscv_pipeline DUT (
    .clk(clk),
    .rst(rst)
);

always #5 clk = ~clk;

initial begin
    clk = 0;
    rst = 1;

    #20;
    rst = 0;

    #500;

    $display("\n========== FINAL STATE ==========");
    $display("PC  = %h", DUT.PC);

    $display("x0 = %0d", DUT.RF.Registers[0]);
    $display("x1 = %0d", DUT.RF.Registers[1]);
    $display("x2 = %0d", DUT.RF.Registers[2]);
    $display("x3 = %0d", DUT.RF.Registers[3]);
    $display("x4 = %0d", DUT.RF.Registers[4]);
    $display("x5 = %0d", DUT.RF.Registers[5]);
    $display("x6 = %0d", DUT.RF.Registers[6]);

    $display("mem0 = %0d", DUT.DMEM.Data_Mem[0]);
    $display("mem1 = %0d", DUT.DMEM.Data_Mem[1]);
    $display("mem2 = %0d", DUT.DMEM.Data_Mem[2]);
    $display("mem3 = %0d", DUT.DMEM.Data_Mem[3]);
    $display("mem4 = %0d", DUT.DMEM.Data_Mem[4]);
    $display("mem5 = %0d", DUT.DMEM.Data_Mem[5]);
    $display("mem6 = %0d", DUT.DMEM.Data_Mem[6]);

    $finish;
end

initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0,tb);
end

endmodule
