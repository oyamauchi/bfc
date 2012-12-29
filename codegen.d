/**
 * x86 codegen. Outputs assembly, which you then have to assemble yourself.
 */

import ir;
import std.container;
import std.conv;
import std.string;
import std.outbuffer;

import std.stdio;

// It's important that memBaseReg is callee-saved.
const string memBaseReg = "%r13";
const string scratchReg = "%r10";
const string[] registers = ["%rbx"];

string codegenOperand(Operand op) {
  switch (op.kind) {
    case OperandKind.None:
      assert(false);
    case OperandKind.Reg:
      return registers[op.number];
    case OperandKind.Const:
      return "$" ~ to!string(op.number);
    case OperandKind.MemReg:
      return "(" ~ memBaseReg ~ ", " ~ registers[op.number] ~ ", 1)";
    case OperandKind.MemConst:
      return to!string(op.number) ~ "(" ~ memBaseReg ~ ")";
    default:
      assert(false);
  }
}

void codegenInstructions(Array!Instruction instrs, ref OutBuffer buf) {
  // Setup the environment: push registers, setup memory
  buf.write(".globl _main\n");
  buf.write("_main:\n");
  buf.write("  pushq %rbp\n");
  buf.write("  pushq %rbx\n");
  buf.write("  pushq " ~ memBaseReg ~ "\n");
  buf.write("  mov $1, %rsi\n");
  buf.write("  mov $30000, %rdi\n");
  buf.write("  call _calloc\n");
  buf.write("  mov %rax, " ~ memBaseReg ~ "\n");
  buf.write("  xor %rbx, %rbx\n");

  // Used for the short jump after the call to getchar
  int shortLabel = 0;

  foreach (ulong idx; 0..instrs.length) {
    Instruction instr = instrs[idx];
    switch (instr.opcode) {
      case Opcode.Add:
      case Opcode.Sub:
        // We're gonna need some real dealing with sizes here
        string suffix = (instr.dest.kind == OperandKind.Reg ? "": "b");
        string op = (instr.opcode == Opcode.Add ? "add" : "sub");
        buf.write(format(
            "  %s%s %s, %s\n", op, suffix,
            codegenOperand(instr.src),
            codegenOperand(instr.dest)));
        break;
      case Opcode.Putchar:
        // We're gonna need some worrying about register-saving here
        buf.write(format("  movzbl %s, %%edi\n",
            codegenOperand(instr.src)));
        buf.write("  call _putchar\n");
        break;
      case Opcode.Getchar:
        buf.write("  call _getchar\n");
        buf.write("  cmpl $0xffffffff, %eax\n");
        buf.write(format("  je LS%d\n", shortLabel));
        buf.write(format("  movb %%al, %s\n", codegenOperand(instr.dest)));
        buf.write(format("LS%d:\n", shortLabel));
        shortLabel++;
        break;
      case Opcode.JumpZ:
      case Opcode.JumpNZ:
        string op = (instr.opcode == Opcode.JumpZ ? "jz" : "jnz");
        buf.write(format("  movb %s, %%r10b\n", codegenOperand(instr.src)));
        buf.write(       "  test %r10b, %r10b\n");
        buf.write(format("  %s L%d\n", op, instr.jumpTarget));
        buf.write(format("L%d:\n", idx));
        break;
      default:
        assert(false);
    }
  }

  buf.write("  popq " ~ memBaseReg ~ "\n");
  buf.write("  popq %rbx\n");
  buf.write("  popq %rbp\n");
  buf.write("  xor %rax, %rax\n");
  buf.write("  retq\n");
}

