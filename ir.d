/**
 * Definitions for bfc's intermediate representation, and a function to
 * transform Brainfuck source into IR.
 */

import std.container;
import std.outbuffer;
import std.stdio;
import std.string;

enum Opcode {
  Load,    // Loads a memory cell into a tmp
  Store,   // Stores a tmp into a memory cell

  Add,     // Adds src1 and src2, puts in dest
  Sub,     // Subtracts src2 from src1, puts in dest
  Putchar, // Prints src. No dest
  Getchar, // Reads a character into dest. No src
  JumpZ,   // If src is zero, jumps to jumpTarget
  JumpNZ,  // If src is nonzero, jumps to jumpTarget

  Zeros,   // Special opcode which defines the pointer register
}

bool opcodeHasDest(Opcode op) {
  switch (op) {
  case Opcode.Load:
  case Opcode.Add:
  case Opcode.Sub:
  case Opcode.Getchar:
  case Opcode.Zeros:
    return true;
  default:
    return false;
  }
}

ulong opcodeSourceCount(Opcode op) {
  switch (op) {
  case Opcode.Getchar:
  case Opcode.Zeros:
    return 0;
  case Opcode.Add:
  case Opcode.Sub:
  case Opcode.Store:
    return 2;
  default:
    return 1;
  }
}

string opcodeName(Opcode op) {
  final switch (op) {
  case Opcode.Load:    return "Load";
  case Opcode.Store:   return "Store";
  case Opcode.Add:     return "Add";
  case Opcode.Sub:     return "Sub";
  case Opcode.Putchar: return "Putchar";
  case Opcode.Getchar: return "Getchar";
  case Opcode.JumpZ:   return "JumpZ";
  case Opcode.JumpNZ:  return "JumpNZ";
  case Opcode.Zeros:   return "Zeros";
  }
}

// Think of this IR as a graph. Instructions are nodes, annotated with an
// opcode. Temps are edges, the means by which values flow between instructions.


struct Temp {
  static int globalTmpNum = 0;
  static Temp* newTemp() {
    return new Temp(false, globalTmpNum++);
  }

  static Temp* newConst(int val) {
    return new Temp(true, val);
  }

  this(bool c, int v) {
    isConst = c;
    tmpNum = v;
  }

  bool isConst;
  int tmpNum;
}

struct Instr {
  Opcode opcode;
  Temp* dest;
  Temp* srcs[];
  ulong jumpTaken;
  ulong jumpNotTaken;
}

class Builder {
  Array!Instr m_instrs;

  Temp* append(Opcode op, Temp* srcs[]) {
    Temp* dst = Temp.newTemp();
    Instr i = Instr(op, dst, srcs);
    m_instrs.insertBack(i);
    return dst;
  }
  void appendJump(Opcode op, Temp* src, ulong taken, ulong notTaken) {
    Instr i = Instr(op, null, [src], taken, notTaken);
    m_instrs.insertBack(i);
  }
}


Array!Instr parse(string source) {
  SList!ulong jumpStack;
  ulong[ulong] jumpTargets;

  foreach (ulong i; 0..source.length) {
    if (source[i] == '[') {
      jumpStack.insertFront(i);
    } else if (source[i] == ']') {
      auto from = jumpStack.front();
      jumpStack.removeFront();
      jumpTargets[from] = i;
      jumpTargets[i] = from;
    }
  }

  Builder b = new Builder();
  auto ptrVal = b.append(Opcode.Zeros, []);

  foreach (ulong i; 0..source.length) {
    switch (source[i]) {
      case '<':
        ptrVal = b.append(Opcode.Sub, [ptrVal, Temp.newConst(1)]);
        break;
      case '>':
        ptrVal = b.append(Opcode.Add, [ptrVal, Temp.newConst(1)]);
        break;
      case '-': {
        auto loadRes = b.append(Opcode.Load, [ptrVal]);
        auto subRes  = b.append(Opcode.Sub, [loadRes, Temp.newConst(1)]);
        b.append(Opcode.Store, [ptrVal, subRes]);
      }
      break;
      case '+': {
        auto loadRes = b.append(Opcode.Load, [ptrVal]);
        auto addRes  = b.append(Opcode.Add, [loadRes, Temp.newConst(1)]);
        b.append(Opcode.Store, [ptrVal, addRes]);
      }
      break;
      case '.': {
        auto loadRes = b.append(Opcode.Load, [ptrVal]);
        b.append(Opcode.Putchar, [loadRes]);
      }
      break;
      case ',': {
        auto getRes = b.append(Opcode.Getchar, []);
        b.append(Opcode.Store, [ptrVal, getRes]);
      }
      break;
      case '[':
        // If the mem cell at the current pointer is zero, jump to the
        // corresponding close bracket. We don't know where that is yet, so put
        // an entry in the queue.
        auto loadRes = b.append(Opcode.Load, [ptrVal]);
        b.appendJump(Opcode.JumpZ, loadRes, jumpTargets[i], i + 1);
        break;
      case ']':
        // If the mem cell at the current pointer is nonzero, jump to the
        // corresponding open bracket: the head of the jump-target stack.
        auto loadRes = b.append(Opcode.Load, [ptrVal]);
        b.appendJump(Opcode.JumpNZ, loadRes, jumpTargets[i], i + 1);
        break;
      default:
        // ignore
    }
  }

  return b.m_instrs;
}

void printInstructions(Array!Instr instrs, OutBuffer buf, ulong start) {
  foreach (Instr instr; instrs) {
    buf.write(format("%4d  ", start));
    start++;

    if (opcodeHasDest(instr.opcode)) {
      buf.write(format("t%d = ", instr.dest.tmpNum));
    }

    buf.write(format("%s", opcodeName(instr.opcode)));

    foreach (ulong i; 0..opcodeSourceCount(instr.opcode)) {
      if (instr.srcs[i].isConst) {
        buf.write(format(" %d", instr.srcs[i].tmpNum));
      } else {
        buf.write(format(" t%d", instr.srcs[i].tmpNum));
      }
    }

    if (instr.opcode == Opcode.JumpZ || instr.opcode == Opcode.JumpNZ) {
      buf.write(format(" -> %d", instr.jumpTaken));
    }
    buf.write("\n");
  }
}
