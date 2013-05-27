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

  Merge,   // Special opcode which captures predecessor variables
}

bool opcodeHasDest(Opcode op) {
  switch (op) {
  case Opcode.Load:
  case Opcode.Add:
  case Opcode.Sub:
  case Opcode.Getchar:
  case Opcode.Merge:
    return true;
  default:
    return false;
  }
}

ulong opcodeSourceCount(Opcode op) {
  switch (op) {
  case Opcode.Getchar:
  case Opcode.Merge: // XXX
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
  case Opcode.Merge:   return "Merge";
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
}

class BasicBlock {
  ulong id;
  Array!Instr instrs;
  Temp* ptrAtExit;

  BasicBlock successors[2];

  this(ulong id) {
    this.id = id;
  }

  void print(OutBuffer buf) {
    buf.write(format("%d:\n", id));
    foreach (Instr instr; instrs) {
      buf.write("    ");
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

      buf.write("\n");
    }

    if (successors[0]) {
      buf.write(format("     -> %d  -> %d", successors[0].id, successors[1].id));
    }

    buf.write("\n\n");
  }
}

class Builder {
  BasicBlock block;

  this(ulong blockId) {
    block = new BasicBlock(blockId);
  }

  Temp* append(Opcode op, Temp* srcs[]) {
    Temp* dst = (opcodeHasDest(op) ? Temp.newTemp() : null);
    Instr i = Instr(op, dst, srcs);
    block.instrs.insertBack(i);
    return dst;
  }
}

BasicBlock parseBasicBlock(string source, ulong idx) {
  Builder b = new Builder(idx);
  auto ptrVal = (idx == 0
                 ? Temp.newConst(0)
                 : b.append(Opcode.Merge, []));

  foreach (ulong i; idx..source.length) {
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
        break;
      }
      case '+': {
        auto loadRes = b.append(Opcode.Load, [ptrVal]);
        auto addRes  = b.append(Opcode.Add, [loadRes, Temp.newConst(1)]);
        b.append(Opcode.Store, [ptrVal, addRes]);
        break;
      }
      case '.': {
        auto loadRes = b.append(Opcode.Load, [ptrVal]);
        b.append(Opcode.Putchar, [loadRes]);
        break;
      }
      case ',': {
        auto getRes = b.append(Opcode.Getchar, []);
        b.append(Opcode.Store, [ptrVal, getRes]);
        break;
      }

      case '[': {
        int openCount = 1;
        ulong afterIdx;
        foreach (j; i + 1..source.length) {
          if (openCount == 0) {
            afterIdx = j;
            break;
          }
          if (source[j] == '[') {
            openCount++;
          } else if (source[j] == ']') {
            openCount--;
          }
        }

        // j is the index we have to jump to
        auto loadRes = b.append(Opcode.Load, [ptrVal]);
        b.append(Opcode.JumpZ, [loadRes]);
        auto taken = parseBasicBlock(source, afterIdx);
        auto notTaken = parseBasicBlock(source, i + 1);

        assert(notTaken.successors[1] is null);
        notTaken.successors[1] = taken;
        b.block.successors[0] = taken;
        b.block.successors[1] = notTaken;
        return b.block;
      }

      case ']': {
        auto loadRes = b.append(Opcode.Load, [ptrVal]);
        b.append(Opcode.JumpNZ, [loadRes]);
        b.block.successors[0] = b.block;
        return b.block;
      }

      default:
        // ignore
        break;
    }
  }

  // This means we've reached the end of the source.
  return b.block;
}
