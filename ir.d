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
  Nop,     // no-op
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
  case Opcode.Nop:
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
  case Opcode.Nop:     return "Nop";
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

  Temp* append(Opcode op, Temp* srcs[]) {
    Temp* dst = (opcodeHasDest(op) ? Temp.newTemp() : null);
    Instr i = Instr(op, dst, srcs);
    instrs.insertBack(i);
    return dst;
  }

  void nopOut(ulong offset) {
    Instr newInst = Instr(Opcode.Nop, null, []);
    instrs[offset] = newInst;
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

class Parser {
  string source;

  // A mapping from bracket-index to target-index. That is, the keys will always
  // point to brackets, and the values will always point to positions
  // immediately after brackets.
  ulong[ulong] jumpTargets;

  // A mapping from block-start to block itself. The keys will always points to
  // positions immediately after brackets.
  BasicBlock[ulong] offsetMap;

  this(string source) {
    this.source = source;

    SList!ulong jumpStack;
    foreach (i; 0..source.length) {
      if (source[i] == '[') {
        jumpStack.insertFront(i);
      } else if (source[i] == ']') {
        // Unbalanced brackets if this fires. TODO: error, not assert
        assert(!jumpStack.empty);

        auto start = jumpStack.front();
        jumpStack.removeFront();
        jumpTargets[i] = start + 1;
        jumpTargets[start] = i + 1;
      }
    }

    // Unbalanced brackets if this fires. TODO: error, not assert
    assert(jumpStack.empty);
  }

  BasicBlock parse() {
    ulong[BasicBlock] blockEnds;

    BasicBlock first = new BasicBlock(0);
    ulong idx = parseBasicBlock(first, 0);
    offsetMap[0] = first;
    blockEnds[first] = idx;

    while (idx < source.length) {
      // idx now points to a bracket
      BasicBlock b = new BasicBlock(idx + 1);
      ulong end = parseBasicBlock(b, idx + 1);
      offsetMap[idx + 1] = b;

      // Record where this block ends, so that we can look up the jump targets
      // later, after all blocks are parsed.
      blockEnds[b] = end;

      idx = end;
    }

    // Populate each block's successors. Look up the jump target, keyed by where
    // the block ended.
    foreach (b; blockEnds.keys) {
      if (blockEnds[b] < source.length) {
        // Fall through
        b.successors[0] = offsetMap[blockEnds[b] + 1];
        // Taken jump
        b.successors[1] = offsetMap[jumpTargets[blockEnds[b]]];
      }
    }

    return first;
  }

  private ulong parseBasicBlock(BasicBlock b, ulong start) {
    auto ptrVal = (start == 0
                   ? Temp.newConst(0)
                   : b.append(Opcode.Merge, []));

    foreach (ulong i; start..source.length) {
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
        auto loadRes = b.append(Opcode.Load, [ptrVal]);
        b.append(Opcode.JumpZ, [loadRes]);
        return i;
      }

      case ']': {
        auto loadRes = b.append(Opcode.Load, [ptrVal]);
        b.append(Opcode.JumpNZ, [loadRes]);
        return i;
      }

      default:
        // ignore
        break;
      }
    }

    // This means we've reached the end of the source.
    return source.length;
  }
}
