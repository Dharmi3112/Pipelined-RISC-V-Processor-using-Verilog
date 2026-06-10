
// ---- ALU -------------------------
module alu(
    input signed[31:0]SrcA,
    input signed[31:0]SrcB,
    input [3:0]ALUControl,
    input [2:0]funct3,
    output reg signed[31:0]ALU_Result,
    output reg zero
);
    always @(*) begin
        case(funct3)
          3'b000: zero = (SrcA == SrcB);  //BEQ
          3'b001: zero = (SrcA != SrcB);  //BNE
          3'b100: zero = (SrcA  < SrcB);  //BLT
          3'b101: zero = (SrcA >= SrcB);  //BGE
            default: zero = 1'b0;
        endcase
    end
  
    always @(*) begin
        case(ALUControl)
            4'b0000: ALU_Result = SrcA + SrcB; //ADD
            4'b0001: ALU_Result = SrcA - SrcB; //SUB
            4'b0010: ALU_Result = SrcA & SrcB; //AND
            4'b0011: ALU_Result = SrcA | SrcB; //OR
          4'b0100: ALU_Result = ($signed(SrcA) < $signed(SrcB)) ? 32'd1 : 32'd0; //SLT
            4'b0101: ALU_Result = SrcA ^ SrcB; //XOR
            4'b0110: ALU_Result = SrcA << SrcB[4:0];
            4'b0111: ALU_Result = $unsigned(SrcA) >> SrcB[4:0]; //SLL
            4'b1000: ALU_Result = SrcA >>> SrcB[4:0]; //SRL
            default: ALU_Result = 32'd0; //SRA
        endcase
    end
endmodule

// ---- Register File ---------------
module Register_File(
    input [4:0]A1,A2,A3,
    input [31:0]WD3,
    input clk,WE3,rst,
    output [31:0]RD1,RD2
);
    reg [31:0]Registers[31:0];
  
    // Read register data with same-cycle write bypassing
    assign RD1 =(A1==0)?32'd0:(WE3 && A3!=0 && A3==A1)?WD3:Registers[A1];
    assign RD2 =(A2==0)?32'd0:(WE3 && A3!=0 && A3==A2)?WD3:Registers[A2];
  
    integer i;
    initial for (i = 0; i < 32; i = i+1) 
      Registers[i] = 0;
  
    always @(posedge clk)
      if (WE3 && A3 != 0)  //WRITE TO ALL REGS EXCEPT X0
          Registers[A3] <= WD3;
endmodule

// ---- Sign Extend  -----------------
module sign_ext(
    input [2:0]Imm_Src,
    input [24:0]d_in,
    output reg [31:0]ImmExt
);
    always @(*) begin
        case(Imm_Src)
          3'b000: ImmExt = {{20{d_in[24]}}, d_in[24:13]}; //I-TYPE
          3'b001: ImmExt = {{20{d_in[24]}}, d_in[24:18], d_in[4:0]}; //S-TYPE
          3'b010: ImmExt = {{19{d_in[24]}}, d_in[24], d_in[0], d_in[23:18], d_in[4:1], 1'b0}; //B-TYPE
          3'b011: ImmExt = {d_in[24:5], 12'b0}; //U-TYPE
          3'b100: ImmExt = {{11{d_in[24]}}, d_in[24], d_in[12:5], d_in[13], d_in[23:14], 1'b0}; //J-TYPE
            default: ImmExt = 32'b0;
        endcase
    end
endmodule

// ---- Data Memory  -----------------
module datamem(
    input [31:0]WD,A,
    input clk,WE,rst,
    output [31:0]RD
);
    reg [31:0]Data_Mem[1023:0];
    assign RD=Data_Mem[A[11:2]]; //READ OPERATION

    always @(posedge clk)
        if (WE) 
          Data_Mem[A[11:2]] <= WD; //WRITE OPERATION
endmodule

// ---- Instruction Memory  ----------
module Instruction_Memory(
    input [31:0]PC,
    output [31:0]instruction
);
    reg [31:0]instruction_memory[1023:0];
    integer i;
  
    initial begin
        for (i = 0; i < 1024; i = i+1)
          instruction_memory[i] = 32'h00000013; //INITIALIZE INS MEM WITH NOP
      $readmemh("program.mem", instruction_memory, 0, 1023);
    end
  
  assign instruction = instruction_memory[PC[11:2]]; //INSTRUCTION FETCH
endmodule

// ---- PC adders / muxes  ----------
module PCPlus4_adder(
  input [31:0] PC,
  output [31:0] PCPlus4
);
    assign PCPlus4 = PC + 32'd4; //NORMAL NEXT PC
endmodule

//----------------------------------
module PCTarget_adder(
  input [31:0] PC, ImmExt,
  output [31:0] PCTarget
);
    assign PCTarget = PC + ImmExt; //BRANCH/JUMP TAGET
endmodule

//----------------------------------
module ALUSrc_mux(
  input [31:0] RD2, ImmExt, 
  input ALU_Src, 
  output [31:0] SrcB
);
    assign SrcB=ALU_Src?ImmExt:RD2; //ALU 2ND SRC
endmodule

//----------------------------------
module result_mux(
    input [31:0]ALUResult,ReadData,PCPlus4,ImmExt,
    input [1:0]ResultSrc,
    output [31:0]Result
);
    assign Result = (ResultSrc==2'b00) ? ALUResult :  //RESULT TO WRITE BACK TO REG
                    (ResultSrc==2'b01) ? ReadData  :
                    (ResultSrc==2'b10) ? PCPlus4   : ImmExt;
endmodule

// ---- Controller  ----------
module Controller_pl(
    input [6:0]OP,
    input [6:0]funct7,
    input [2:0]funct3,
    
    output reg mem_write,
    output reg ALU_Src,
    output reg reg_write,
    output reg [1:0]ResultSrc,
    output reg [3:0]ALUControl,
    output reg [2:0]Imm_Src,
    output reg WD3_Src,
    output reg [2:0]branch_op //BRANCH OPERATION SELECTION
);
    wire [9:0]check = {funct7, funct3};
    reg [1:0]ALUOp;

    always @(*) begin
        // defaults
        reg_write  = 0; 
        mem_write = 0; ALU_Src  = 0;
        ResultSrc  = 2'b00; 
        Imm_Src = 3'b000;
        WD3_Src    = 0;     
        ALUOp   = 2'b00;
        branch_op  = 2'b00;

        case (OP)
           // R-type instructions
            7'b0110011: begin 
                        reg_write=1; 
                        ALUOp=2'b00;
            			end  
          
          // I-type ALU instructions
          	7'b0010011: begin 
                        reg_write=1; 
                        ALU_Src=1; 
                        ALUOp=2'b01; 
                        end  
          // Load instructions
          	7'b0000011: begin
                        reg_write=1; 
                        ALU_Src=1;
                        ResultSrc=2'b01; 
                        ALUOp=2'b10;
            			end 
          // S-type instruction
          	7'b0100011: begin 
               			mem_write=1;
              			ALU_Src=1; 
              			Imm_Src=3'b001;
              			ALUOp=2'b10; 
            			end  
           // B-type instruction
          	7'b1100011: begin                                            
               			Imm_Src = 3'b010; 
              			ALU_Src = 0;
              			ALUOp = 2'b10;
                
              			case(funct3)
                            3'b000: branch_op = 3'b001; // BEQ
                            3'b001: branch_op = 3'b010; // BNE
                            3'b100: branch_op = 3'b011; // BLT
                            3'b101: branch_op = 3'b110; // BGE
                        default: branch_op = 3'b000;
                        endcase
                        end
          
           // U-type instruction
            7'b0110111: begin 
                        reg_write=1; 
              			Imm_Src=3'b011;
              			ResultSrc=2'b11;
            			end 
          
           // J-type instruction
            7'b1101111: begin               //JAL
                        reg_write=1;
                        Imm_Src=3'b100;
                        WD3_Src=1;
                        branch_op=3'b100;
                       end
          
          	7'b1100111: begin              //JALR
                        reg_write=1;
                        ALU_Src=1;
                        WD3_Src=1;
                        branch_op=3'b101;
                        end
        endcase
    end

    always @(*) begin
        ALUControl = 4'b0000;
      
        case (ALUOp)
          
          	// R-type ALU operations
            2'b00: ALUControl =             
                (check==10'b0000000_000) ? 4'b0000 : // ADD
                (check==10'b0100000_000) ? 4'b0001 : // SUB
                (check==10'b0000000_111) ? 4'b0010 : // AND
                (check==10'b0000000_110) ? 4'b0011 : // OR
                (check==10'b0000000_010) ? 4'b0100 : // SLT
                (check==10'b0000000_100) ? 4'b0101 : // XOR
                (check==10'b0000000_001) ? 4'b0110 : // SLL
                (check==10'b0000000_101) ? 4'b0111 : // SRL
                (check==10'b0100000_101) ? 4'b1000 : 4'b0000; // SRA
          
          	// I-type ALU operations
            2'b01: ALUControl =             
                (funct3==3'b000)? 4'b0000 : // ADDI
                (funct3==3'b111)? 4'b0010 : // ANDI
                (funct3==3'b110)? 4'b0011 : // ORI
                (funct3==3'b100)? 4'b0101 : // XORI
                (funct3==3'b010)? 4'b0100 : // SLTI
                (funct3==3'b001 && funct7==7'b0000000)? 4'b0110 : // SLLI
                (funct3==3'b101 && funct7==7'b0000000)? 4'b0111 : // SRLI
                (funct3==3'b101 && funct7==7'b0100000)? 4'b1000 : 4'b0000; // SRAI
            2'b10: ALUControl = 4'b0000;    // BRANCH/LOAD/STORE -> SUB/ADD (ADD for ld/st)
            2'b11: ALUControl = 4'b0000;    // JALR -> ADD
        endcase
    end
endmodule

// Hazard Detection Unit
module hazard_unit(
    input [4:0]id_rs1,id_rs2, // source regs in ID stage
    input [4:0]ex_rd,         // dest reg in EX stage
    input ex_mem_re,          // is EX stage a load?
    input take_branch,        // branch/jump resolved in EX
    output stall_if,          // freeze PC
    output stall_id,          // freeze IF/ID register
    output flush_ex           // insert NOP into ID/EX register
);
    // Load-use: EX is a load and its rd matches ID's rs1 or rs2
    wire load_use = ex_mem_re &&
                    ((ex_rd == id_rs1 && id_rs1 != 0) ||
                     (ex_rd == id_rs2 && id_rs2 != 0));

    assign stall_if = load_use;    // Prevents PC from updating
    assign stall_id = load_use;    // Prevents IF/ID register from updating
    assign flush_ex = load_use | take_branch; // Clears ID/EX register and inserts NOP
endmodule

// Forwarding Unit
module forwarding_unit(
    input [4:0]ex_rs1, ex_rs2,   // source regs in EX stage
    input [4:0]mem_rd, wb_rd,    // dest regs in MEM/WB stages
    input mem_reg_we,       // MEM stage writes a register?
    input wb_reg_we,        // WB  stage writes a register?
    output reg[1:0]fwd_a_sel,    // mux select for ALU input A
    output reg[1:0]fwd_b_sel     // mux select for ALU input B
);
    always @(*) begin
        // Forward A
        if(mem_reg_we && mem_rd != 0 && mem_rd == ex_rs1)
          fwd_a_sel = 2'b10;
        else if (wb_reg_we  && wb_rd  != 0 && wb_rd  == ex_rs1) 
          fwd_a_sel = 2'b01;
        else                                                     
          fwd_a_sel = 2'b00;
      
        // Forward B
        if(mem_reg_we && mem_rd != 0 && mem_rd == ex_rs2) 
          fwd_b_sel = 2'b10;
        else if (wb_reg_we  && wb_rd  != 0 && wb_rd  == ex_rs2) 
          fwd_b_sel = 2'b01;
        else                                                     
          fwd_b_sel = 2'b00;
    end
endmodule

// Pipeline Registers

// ---- IF/ID register -------------------------------------------------
module pipe_IF_ID(
    input clk, rst, flush, stall,
    input [31:0]pc_in, instr_in,
    output reg[31:0]pc_out, instr_out
);
    always @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            pc_out    <= 0;
            instr_out <= 32'h00000013; // NOP
        end else if (!stall) begin
            pc_out    <= pc_in;
            instr_out <= instr_in;
        end
    end
endmodule

// ---- ID/EX register -------------------------------------------------
module pipe_ID_EX(
    input clk, rst, flush,
    input mem_write_in, ALU_Src_in, reg_write_in,
    input [1:0]ResultSrc_in,
    input [3:0]ALUControl_in,
  	input [2:0] Imm_Src_in,
    input WD3_Src_in,
    input [2:0]branch_op_in,
    input mem_re_in,       

    input [31:0]pc_in, RD1_in, RD2_in, ImmExt_in,
    input [4:0]rs1_in, rs2_in, rd_in,
    input [2:0]funct3_in,
  
    output reg mem_write_out, ALU_Src_out, reg_write_out,
    output reg [1:0]ResultSrc_out,
    output reg [3:0]ALUControl_out,
    output reg [2:0]Imm_Src_out,
    output reg WD3_Src_out,
    output reg [2:0] branch_op_out,
    output reg mem_re_out,
    output reg [31:0]pc_out, RD1_out, RD2_out, ImmExt_out,
    output reg [4:0]rs1_out, rs2_out, rd_out,
    output reg [2:0]funct3_out
);
    always @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            mem_write_out<=0; 
            ALU_Src_out<=0; 
            reg_write_out<=0;
            ResultSrc_out<=0;
            ALUControl_out<=0; 
            Imm_Src_out<=0;
            WD3_Src_out<=0;
            branch_op_out<=0;
            mem_re_out<=0;
            pc_out<=0;
            RD1_out<=0; 
            RD2_out<=0;
            ImmExt_out<=0;
            rs1_out<=0; 
            rs2_out<=0;
            rd_out<=0; 
            funct3_out<=0;
        end 
      
      else begin
            mem_write_out<= mem_write_in;  
            ALU_Src_out<= ALU_Src_in;
            reg_write_out<= reg_write_in; 
            ResultSrc_out<= ResultSrc_in;
            ALUControl_out<= ALUControl_in; 
            Imm_Src_out<= Imm_Src_in;
            WD3_Src_out<= WD3_Src_in;   
            branch_op_out<= branch_op_in;
            mem_re_out<= mem_re_in;
            pc_out<= pc_in;   
            RD1_out<= RD1_in;
            RD2_out<= RD2_in;  
            ImmExt_out<= ImmExt_in;
            rs1_out<= rs1_in; 
            rs2_out<= rs2_in;
            rd_out<= rd_in;   
            funct3_out<= funct3_in;
        end
    end
endmodule

// ---- EX/MEM register ------------------------------------------------
module pipe_EX_MEM(
    input clk, rst,
    input mem_write_in, reg_write_in, WD3_Src_in,
    input [1:0]ResultSrc_in,
    input [31:0]ALUResult_in, RD2_in, PCPlus4_in, ImmExt_in,
    input [4:0]rd_in,
    output reg mem_write_out, reg_write_out, WD3_Src_out,
    output reg [1:0]ResultSrc_out,
    output reg [31:0]ALUResult_out, RD2_out, PCPlus4_out, ImmExt_out,
    output reg [4:0]rd_out
);
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_write_out<=0; 
            reg_write_out<=0;
            WD3_Src_out<=0;
            ResultSrc_out<=0; 
            ALUResult_out<=0;
            RD2_out<=0;
            PCPlus4_out<=0; 
            ImmExt_out<=0; 
            rd_out<=0;
        end
      
      else begin
            mem_write_out<= mem_write_in;  
            reg_write_out<= reg_write_in;
            WD3_Src_out<= WD3_Src_in;   
            ResultSrc_out<= ResultSrc_in;
            ALUResult_out<= ALUResult_in;  
            RD2_out<= RD2_in;
            PCPlus4_out<= PCPlus4_in;   
            ImmExt_out<= ImmExt_in;
            rd_out<= rd_in;
        end
    end
endmodule

// ---- MEM/WB register ------------------------------------------------
module pipe_MEM_WB(
    input clk, rst,
    input reg_write_in, WD3_Src_in,
    input [1:0]ResultSrc_in,
    input [31:0]ALUResult_in, ReadData_in, PCPlus4_in, ImmExt_in,
    input [4:0]rd_in,
    output reg reg_write_out, WD3_Src_out,
    output reg [1:0]ResultSrc_out,
    output reg [31:0]ALUResult_out, ReadData_out, PCPlus4_out, ImmExt_out,
    output reg [4:0]rd_out
);
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            reg_write_out<=0; 
            WD3_Src_out<=0;
            ResultSrc_out<=0;
            ALUResult_out<=0; 
            ReadData_out<=0; 
            PCPlus4_out<=0;
            ImmExt_out<=0; 
            rd_out<=0;
        end else begin
            reg_write_out<= reg_write_in; 
            WD3_Src_out<= WD3_Src_in;
            ResultSrc_out<= ResultSrc_in;  
            ALUResult_out<= ALUResult_in;
            ReadData_out<= ReadData_in;   
            PCPlus4_out<= PCPlus4_in;
            ImmExt_out<= ImmExt_in; 
            rd_out<= rd_in;
        end
    end
endmodule

// Top-level module: riscv_pipeline

module riscv_pipeline(
    input clk,
    input rst
);

// IF STAGE wires
wire [31:0] pc_if, pc_next_if, pc_plus4_if;
wire [31:0] instr_if;
wire stall_if, stall_id, flush_ex;
wire take_branch;
wire [31:0]branch_target;

// PC register
reg [31:0] PC;
always @(posedge clk or posedge rst)
    if (rst)       
      PC <= 32'd0;
    else if (!stall_if) 
      PC <= pc_next_if;

assign pc_if = PC;

Instruction_Memory IMEM (
  .PC(pc_if), 
  .instruction(instr_if)
);
  
PCPlus4_adder PC4_IF (
  .PC(pc_if), 
  .PCPlus4(pc_plus4_if)
);

// Branch target comes from EX stage (computed below)
assign pc_next_if = take_branch ? branch_target_final : pc_plus4_if;

// IF/ID pipeline register
wire [31:0] pc_id, instr_id;
pipe_IF_ID IFID (
    .clk(clk),
    .rst(rst),
    .flush(take_branch), 
    .stall(stall_id),
    .pc_in(pc_if),
    .instr_in(instr_if),
    .pc_out(pc_id), 
    .instr_out(instr_id)
);

// ID STAGE
wire [6:0] op_id   = instr_id[6:0];
wire [4:0] rs1_id  = instr_id[19:15];
wire [4:0] rs2_id  = instr_id[24:20];
wire [4:0] rd_id   = instr_id[11:7];
wire [2:0] funct3_id = instr_id[14:12];
wire [6:0] funct7_id = instr_id[31:25];

// Control signals
wire        mem_write_id, ALU_Src_id, reg_write_id, WD3_Src_id;
wire [1:0] ResultSrc_id;
wire [2:0] branch_op_id;
wire [3:0]  ALUControl_id;
wire [2:0]  Imm_Src_id;
wire        mem_re_id;  

Controller_pl CU (
    .OP(op_id), 
    .funct7(funct7_id), 
    .funct3(funct3_id),
    .mem_write(mem_write_id), 
    .ALU_Src(ALU_Src_id),
    .reg_write(reg_write_id), 
    .ResultSrc(ResultSrc_id),
    .ALUControl(ALUControl_id), 
    .Imm_Src(Imm_Src_id),
    .WD3_Src(WD3_Src_id), 
    .branch_op(branch_op_id)
);
assign mem_re_id = (op_id == 7'b0000011); // LOAD opcode

// WB stage data (comes from bottom of pipeline, used for writeback)
wire [31:0] wb_result, wb_data_final;
wire [4:0]  rd_wb;
wire        reg_write_wb, WD3_Src_wb;
wire [1:0]  ResultSrc_wb;
wire [31:0] ALUResult_wb, ReadData_wb, PCPlus4_wb, ImmExt_wb;

result_mux RESMUX_WB (
    .ALUResult(ALUResult_wb), 
    .ReadData(ReadData_wb),
    .PCPlus4(PCPlus4_wb), 
    .ImmExt(ImmExt_wb),
    .ResultSrc(ResultSrc_wb),
    .Result(wb_result)
);
// WD3_Src selects PC+4 (for JAL/JALR) vs Result
assign wb_data_final = WD3_Src_wb ? PCPlus4_wb : wb_result;

wire [31:0] RD1_id, RD2_id;
Register_File RF (
    .A1(rs1_id),
    .A2(rs2_id), 
    .A3(rd_wb),
    .WD3(wb_data_final), 
    .clk(clk),
    .WE3(reg_write_wb),
    .rst(rst),
    .RD1(RD1_id), 
    .RD2(RD2_id)
);

wire [31:0] ImmExt_id;
sign_ext SE (
    .Imm_Src(Imm_Src_id),
    .d_in(instr_id[31:7]),
    .ImmExt(ImmExt_id)
);

// ID/EX pipeline register
wire mem_write_ex, ALU_Src_ex, reg_write_ex, WD3_Src_ex, mem_re_ex;
wire [1:0]ResultSrc_ex;
wire [2:0]branch_op_ex;
wire [3:0]ALUControl_ex;
wire [2:0]Imm_Src_ex;
wire [31:0]pc_ex, RD1_ex, RD2_ex, ImmExt_ex;
wire [4:0]rs1_ex, rs2_ex, rd_ex;
wire [2:0]funct3_ex;

pipe_ID_EX IDEX (
    .clk(clk), 
    .rst(rst), 
    .flush(flush_ex),
    .mem_write_in(mem_write_id), 
    .ALU_Src_in(ALU_Src_id),
    .reg_write_in(reg_write_id),
    .ResultSrc_in(ResultSrc_id),
    .ALUControl_in(ALUControl_id), 
    .Imm_Src_in(Imm_Src_id),
    .WD3_Src_in(WD3_Src_id), 
    .branch_op_in(branch_op_id),
    .mem_re_in(mem_re_id),
    .pc_in(pc_id), 
    .RD1_in(RD1_id), 
    .RD2_in(RD2_id),
    .ImmExt_in(ImmExt_id),
    .rs1_in(rs1_id), 
    .rs2_in(rs2_id),
    .rd_in(rd_id), 
    .funct3_in(funct3_id),
    .mem_write_out(mem_write_ex), 
    .ALU_Src_out(ALU_Src_ex),
    .reg_write_out(reg_write_ex), 
    .ResultSrc_out(ResultSrc_ex),
    .ALUControl_out(ALUControl_ex), 
    .Imm_Src_out(Imm_Src_ex),
    .WD3_Src_out(WD3_Src_ex), 
    .branch_op_out(branch_op_ex),
    .mem_re_out(mem_re_ex),
    .pc_out(pc_ex), 
    .RD1_out(RD1_ex),
    .RD2_out(RD2_ex),
    .ImmExt_out(ImmExt_ex), 
    .rs1_out(rs1_ex), 
    .rs2_out(rs2_ex),
    .rd_out(rd_ex), 
    .funct3_out(funct3_ex)
);

// Hazard & Forwarding
wire [1:0] fwd_a_sel, fwd_b_sel;

// MEM stage destination (needed by forwarding unit)
wire [4:0]  rd_mem;
wire        reg_write_mem;

forwarding_unit FWD (
    .ex_rs1(rs1_ex), 
    .ex_rs2(rs2_ex),
    .mem_rd(rd_mem),  
    .mem_reg_we(reg_write_mem),
    .wb_rd(rd_wb),     
    .wb_reg_we(reg_write_wb),
    .fwd_a_sel(fwd_a_sel),
    .fwd_b_sel(fwd_b_sel)
);

hazard_unit HAZ (
    .id_rs1(rs1_id), 
    .id_rs2(rs2_id),
    .ex_rd(rd_ex), 
    .ex_mem_re(mem_re_ex),
    .take_branch(take_branch),
    .stall_if(stall_if), 
    .stall_id(stall_id), 
    .flush_ex(flush_ex)
);

// EX STAGE
wire [31:0] ALUResult_mem; // from EX/MEM register (declared below)

wire [31:0] SrcA = (fwd_a_sel == 2'b00) ? RD1_ex :
                   (fwd_a_sel == 2'b01) ? wb_data_final :
                                          ALUResult_mem;

wire [31:0] SrcB_pre = (fwd_b_sel == 2'b00) ? RD2_ex :
                       (fwd_b_sel == 2'b01) ? wb_data_final :
                                              ALUResult_mem;

wire [31:0] SrcB;
ALUSrc_mux ALUMUX (
  .RD2(SrcB_pre), 
  .ImmExt(ImmExt_ex), 
  .ALU_Src(ALU_Src_ex),
  .SrcB(SrcB));

wire [31:0] ALUResult_ex;
wire        zero_ex;
alu ALU (
    .SrcA(SrcA), 
    .SrcB(SrcB),
    .ALUControl(ALUControl_ex), 
    .funct3(funct3_ex),
    .ALU_Result(ALUResult_ex),
    .zero(zero_ex)
);

// Branch resolution
reg branch_taken;
always @(*) begin
    case(branch_op_ex)
        3'b001: branch_taken = zero_ex; // BEQ
        3'b010: branch_taken = zero_ex; // BNE
        3'b011: branch_taken = zero_ex; // BLT
        3'b110: branch_taken = zero_ex; // BGE
        3'b100: branch_taken = 1'b1;    // JAL
        3'b101: branch_taken = 1'b1;    // JALR
        default: branch_taken = 1'b0;
    endcase
end
assign take_branch = branch_taken;

wire is_jalr = (instr_id[6:0] == 7'b1100111); 
  
PCTarget_adder PCTGT (
    .PC(pc_ex),
    .ImmExt(ImmExt_ex), 
    .PCTarget(branch_target)
);

wire [31:0] branch_target_final;
assign branch_target_final=(branch_op_ex == 3'b101)?(ALUResult_ex & ~32'd1):branch_target;

wire [31:0] pc_plus4_ex;
  
PCPlus4_adder PC4_EX (
  .PC(pc_ex), 
  .PCPlus4(pc_plus4_ex)
);

// EX/MEM pipeline register
wire mem_write_mem, WD3_Src_mem;
wire [1:0]ResultSrc_mem;
wire [31:0]RD2_mem, PCPlus4_mem, ImmExt_mem;

pipe_EX_MEM EXMEM (
    .clk(clk), 
    .rst(rst),
    .mem_write_in(mem_write_ex), 
    .reg_write_in(reg_write_ex),
    .WD3_Src_in(WD3_Src_ex), 
    .ResultSrc_in(ResultSrc_ex),
    .ALUResult_in(ALUResult_ex),
    .RD2_in(SrcB_pre), 
    .PCPlus4_in(pc_plus4_ex), 
    .ImmExt_in(ImmExt_ex),
    .rd_in(rd_ex),
    .mem_write_out(mem_write_mem),
    .reg_write_out(reg_write_mem),
    .WD3_Src_out(WD3_Src_mem),
    .ResultSrc_out(ResultSrc_mem),
    .ALUResult_out(ALUResult_mem), 
    .RD2_out(RD2_mem),
    .PCPlus4_out(PCPlus4_mem), 
    .ImmExt_out(ImmExt_mem),
    .rd_out(rd_mem)
);

// MEM STAGE
wire [31:0] ReadData_mem;
datamem DMEM (
    .WD(RD2_mem), 
    .A(ALUResult_mem),
    .clk(clk), .WE(mem_write_mem), 
    .rst(rst),
    .RD(ReadData_mem)
);
  
// MEM/WB pipeline register
pipe_MEM_WB MEMWB (
    .clk(clk), 
    .rst(rst),
    .reg_write_in(reg_write_mem),
    .WD3_Src_in(WD3_Src_mem),
    .ResultSrc_in(ResultSrc_mem),
    .ALUResult_in(ALUResult_mem),
    .ReadData_in(ReadData_mem),
    .PCPlus4_in(PCPlus4_mem), 
    .ImmExt_in(ImmExt_mem),
    .rd_in(rd_mem),
    .reg_write_out(reg_write_wb), 
    .WD3_Src_out(WD3_Src_wb),
    .ResultSrc_out(ResultSrc_wb),
    .ALUResult_out(ALUResult_wb), 
    .ReadData_out(ReadData_wb),
    .PCPlus4_out(PCPlus4_wb), 
    .ImmExt_out(ImmExt_wb),
    .rd_out(rd_wb)
);
endmodule