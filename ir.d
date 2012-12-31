/**
 * Definitions for bfc's intermediate representation, and a function to
 * transform Brainfuck source into IR.
 */

import std.container;
import std.outbuffer;
import std.stdio;
import std.string;

enum Opcode {
  Add,     // Adds src to dest
  Sub,     // Subtracts src from dest
  Putchar, // Prints src. No dest
  Getchar, // Reads a character into dest. No src
  JumpZ,   // If src is zero, jumps to jumpTarget
  JumpNZ,  // If src is nonzero, jumps to jumpTarget
}

enum OperandKind {
  None,
  Reg,
  Const,
  MemReg,
  MemConst
}

struct Operand {
  OperandKind kind;
  int number;
  static Operand None() {
    return Operand(OperandKind.None);
  }
  static Operand Reg(int regnum) {
    return Operand(OperandKind.Reg, regnum);
  }
  static Operand Const(int value) {
    return Operand(OperandKind.Const, value);
  }
  static Operand MemReg(int regnum) {
    return Operand(OperandKind.MemReg, regnum);
  }
  static Operand MemConst(int value) {
    return Operand(OperandKind.MemConst, value);
  }
}

struct Instruction {
  Opcode opcode;
  Operand dest;
  Operand src;
  ulong jumpTarget;
}


Array!Instruction parse(string source) {
  Array!Instruction result;
  SList!ulong jumpTargets;

  foreach (ulong i; 0..source.length) {
    switch (source[i]) {
      case '<':
        result.insertBack(
            Instruction(Opcode.Sub, Operand.Reg(0), Operand.Const(1)));
        break;
      case '>':
        result.insertBack(
            Instruction(Opcode.Add, Operand.Reg(0), Operand.Const(1)));
        break;
      case '-':
        result.insertBack(
            Instruction(Opcode.Sub, Operand.MemReg(0), Operand.Const(1)));
        break;
      case '+':
        result.insertBack(
            Instruction(Opcode.Add, Operand.MemReg(0), Operand.Const(1)));
        break;
      case '.':
        result.insertBack(
            Instruction(Opcode.Putchar, Operand.None(), Operand.MemReg(0)));
        break;
      case ',':
        result.insertBack(
            Instruction(Opcode.Getchar, Operand.MemReg(0), Operand.None()));
        break;
      case '[':
        // If the mem cell at the current pointer is zero, jump to the
        // corresponding close bracket. We don't know where that is yet, so put
        // an entry in the queue.
        ulong toModify = result.length;
        result.insertBack(
            Instruction(Opcode.JumpZ,
              Operand.None(), Operand.MemReg(0), 0xdeadbeef));
        jumpTargets.insertFront(toModify);
        break;
      case ']':
        // If the mem cell at the current pointer is nonzero, jump to the
        // corresponding open bracket: the head of the jump-target stack.
        ulong toModify = jumpTargets.front();
        jumpTargets.removeFront();

        Instruction prevJump = result[toModify];
        assert(prevJump.opcode == Opcode.JumpZ);
        assert(prevJump.jumpTarget == 0xdeadbeef);
        prevJump.jumpTarget = result.length + 1;
        result[toModify] = prevJump;

        result.insertBack(
            Instruction(Opcode.JumpNZ,
              Operand.None(), Operand.MemReg(0), toModify + 1));
        break;
      default:
        // ignore
    }
  }
  assert(jumpTargets.empty());
  return result;
}

string printOperand(Operand op) {
  switch (op.kind) {
    case OperandKind.Const:    return format("%d", op.number);
    case OperandKind.Reg:      return format("r%d", op.number);
    case OperandKind.MemConst: return format("[%d]", op.number);
    case OperandKind.MemReg:   return format("[r%d]", op.number);
    default:                   assert(false);
  }
}

void printInstructions(Array!Instruction instrs, OutBuffer buf, ulong start) {
  foreach (Instruction instr; instrs) {
    buf.write(format("%4d  ", start));
    start++;

    switch (instr.opcode) {
      case Opcode.Add:
        buf.write(format("Add %s, %s\n", printOperand(instr.dest),
              printOperand(instr.src)));
        break;
      case Opcode.Sub:
        buf.write(format("Sub %s, %s\n", printOperand(instr.dest),
              printOperand(instr.src)));
        break;
      case Opcode.Putchar:
        buf.write(format("Putchar %s\n", printOperand(instr.src)));
        break;
      case Opcode.Getchar:
        buf.write(format("%s = Getchar\n", printOperand(instr.dest)));
        break;
      case Opcode.JumpZ:
        buf.write(format("JumpZ %s, %d\n", printOperand(instr.src),
              instr.jumpTarget));
        break;
      case Opcode.JumpNZ:
        buf.write(format("JumpNZ %s, %d\n", printOperand(instr.src),
              instr.jumpTarget));
        break;
      default:
        assert(false);
    }
  }
}

