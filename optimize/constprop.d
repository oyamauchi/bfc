
module optimize.constprop;
import optimize.cfg;
import ir;

import std.container;

void constantPropagate(ref BasicBlock bb) {
  assert(bb.predecessors.length == 0);

  int[int] regnumToVal;
  regnumToVal[0] = 0;

  foreach (ulong i; 0..bb.instrs.length) {
    Instruction instr = bb.instrs[i];

    // Propagate known values in.
    if (instr.opcode != Opcode.Getchar) {
      // All non-getchar instructions have sources. Here we can just sub in
      // known constant values; the src isn't being modified.
      switch (instr.src.kind) {
      case OperandKind.Reg:
        if (instr.src.number in regnumToVal) {
          instr.src.kind = OperandKind.Const;
          instr.src.number = regnumToVal[instr.src.number];
        }
        break;
      case OperandKind.MemReg:
        if (instr.src.number in regnumToVal) {
          instr.src.kind = OperandKind.MemConst;
          instr.src.number = regnumToVal[instr.src.number];
        }
        break;
      default:
        break;
      }
    }

    if (instr.opcode == Opcode.Add ||
        instr.opcode == Opcode.Sub ||
        instr.opcode == Opcode.Getchar) {
      // These instructions have dests, which they will modify. If the dest is a
      // memory reference, we can sub in a constant value of the address if we
      // know it. If it's a register, we have to update our map.
      switch (instr.dest.kind) {
      case OperandKind.MemReg:
        // Easy: just sub in constant value if known.
        if (instr.dest.number in regnumToVal) {
          instr.dest.kind = OperandKind.MemConst;
          instr.dest.number = regnumToVal[instr.dest.number];
        }
        break;
      case OperandKind.Reg:
        // We have to update the constant-value map. This might cause us to lose
        // track of the dest.
        if (instr.dest.number in regnumToVal) {
          if ((instr.opcode == Opcode.Add || instr.opcode == Opcode.Sub) &&
              instr.src.kind == OperandKind.Const) {
            // The src won't be a register of known constant value, because
            // that's already been propagated in, above
            int prevVal = regnumToVal[instr.dest.number];
            int srcVal = instr.src.number;
            int newVal = (instr.opcode == Opcode.Add
                          ? prevVal + srcVal
                          : prevVal - srcVal);
            regnumToVal[instr.dest.number] = newVal;
          } else {
            // Either a getchar, or a reg-reg add/sub. Now all bets are off.
            regnumToVal.remove(instr.dest.number);
          }
        }
        break;
      default:
        break;
      }
    }

    bb.instrs[i] = instr;
  }

  bb.regnumToVal = regnumToVal;
}
