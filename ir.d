/**
 * Definitions for bfc's intermediate representation, and a function to
 * transform Brainfuck source into IR.
 */

import std.container;

import std.stdio;

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
        prevJump.jumpTarget = result.length;
        result[toModify] = prevJump;

        result.insertBack(
            Instruction(Opcode.JumpNZ,
              Operand.None(), Operand.MemReg(0), toModify));

        // This generates jumps to jump instructions, which is useless,
        // technically. However, this setup is convenient for codegen, and
        // doesn't mean we generate worse code. The target of every jump is a
        // jump instruction, which makes it easy to generate labels during
        // codegen. We avoid useless computation by putting the label after the
        // code for evaluating the condition.
        break;
      default:
        // ignore
    }
  }
  assert(jumpTargets.empty());
  return result;
}