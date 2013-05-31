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

class Temp {
  private static int globalTempNum = 0;
  static Temp newByteTemp() {
    Temp t = new Temp();
    t.isConst = false;
    t.isWord = false;
    t.tempNum = globalTempNum++;
    return t;
  }

  static Temp newWordTemp() {
    Temp t = new Temp();
    t.isConst = false;
    t.isWord = true;
    t.tempNum = globalTempNum++;
    return t;
  }

  static Temp newConstByte(byte val) {
    Temp t = new Temp();
    t.isConst = true;
    t.isWord = false;
    t.byteConstVal = val;
    return t;
  }

  static Temp newConstWord(long val) {
    Temp t = new Temp();
    t.isConst = true;
    t.isWord = true;
    t.wordConstVal = val;
    return t;
  }

  // The instruction that produced this temp.
  Instr inst;

  bool isConst;
  bool isWord;  // size
  union {
    byte byteConstVal;
    long wordConstVal;
    int tempNum;
  }
}

class Instr {
  Opcode opcode;
  Temp dest;
  Temp srcs[];

  this(Opcode opcode, Temp dest, Temp srcs[]) {
    this.opcode = opcode;
    this.dest = dest;
    this.srcs = srcs;
  }

  bool computeResultIsWord() {
    switch (opcode) {
    case Opcode.Load: case Opcode.Store: case Opcode.Getchar:
      return false;
    case Opcode.Merge:
      return true;
    case Opcode.Add: case Opcode.Sub:
      assert(srcs.length == 2);
      assert(srcs[0].isWord == srcs[1].isWord);
      return srcs[0].isWord;

    default:
      assert(!opcodeHasDest(opcode));
    }
    assert(false);
  }
}

class BasicBlock {
  ulong id;
  Array!Instr instrs;
  Temp ptrAtExit;

  BasicBlock successors[2];

  this(ulong id) {
    this.id = id;
  }

  Temp append(Opcode op, Temp srcs[]) {
    Instr i = new Instr(op, null, srcs);
    Temp dest = null;
    if (opcodeHasDest(op)) {
      dest = (i.computeResultIsWord() ? Temp.newWordTemp() : Temp.newByteTemp());
      dest.inst = i;
    }
    i.dest = dest;
    instrs.insertBack(i);
    return dest;
  }

  void nopOut(ulong offset) {
    instrs[offset].opcode = Opcode.Nop;
    instrs[offset].dest = null;
    instrs[offset].srcs = [];
  }

  void print(OutBuffer buf) {
    buf.write(format("%d:\n", id));
    foreach (Instr instr; instrs) {
      buf.write("    ");
      if (opcodeHasDest(instr.opcode)) {
        buf.write(format("t%d%s = ", instr.dest.tempNum, instr.dest.isWord ? "L" : ""));
      }

      buf.write(format("%s", opcodeName(instr.opcode)));

      foreach (ulong i; 0..opcodeSourceCount(instr.opcode)) {
        if (instr.srcs[i].isConst) {
          if (instr.srcs[i].isWord) {
            buf.write(format(" %dL", instr.srcs[i].wordConstVal));
          } else {
            buf.write(format(" %d", instr.srcs[i].byteConstVal));
          }
        } else {
          buf.write(format(" t%d", instr.srcs[i].tempNum));
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
                   ? Temp.newConstWord(0)
                   : b.append(Opcode.Merge, []));

    foreach (ulong i; start..source.length) {
      switch (source[i]) {
      case '<':
        ptrVal = b.append(Opcode.Sub, [ptrVal, Temp.newConstWord(1)]);
        break;
      case '>':
        ptrVal = b.append(Opcode.Add, [ptrVal, Temp.newConstWord(1)]);
        break;
      case '-': {
        auto loadRes = b.append(Opcode.Load, [ptrVal]);
        auto subRes  = b.append(Opcode.Sub, [loadRes, Temp.newConstByte(1)]);
        b.append(Opcode.Store, [ptrVal, subRes]);
        break;
      }
      case '+': {
        auto loadRes = b.append(Opcode.Load, [ptrVal]);
        auto addRes  = b.append(Opcode.Add, [loadRes, Temp.newConstByte(1)]);
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
        b.ptrAtExit = ptrVal;
        return i;
      }

      case ']': {
        auto loadRes = b.append(Opcode.Load, [ptrVal]);
        b.append(Opcode.JumpNZ, [loadRes]);
        b.ptrAtExit = ptrVal;
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
