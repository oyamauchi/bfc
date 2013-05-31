/**
 * Constant folding and propagation.
 */

module opt.constprop;

import ir;

/**
 * The basic strategy of constant folding is to examine pairs of dependent
 * arithmetic ops. If two of the three leaves involved are constant, we can
 * replace the pair with a single arithmetic op.
 *
 * Returns whether any edits were made.
 */
private bool constantFold(BasicBlock b) {
  bool changed = false;

  foreach (i; 0..b.instrs.length) {
    auto inst = b.instrs[i];
    if (inst.opcode != Opcode.Add && inst.opcode != Opcode.Sub) {
      continue;
    }

    auto wordOp = function (Opcode op, Temp t1, Temp t2) {
      assert(t1.isWord && t2.isWord);
      return (op == Opcode.Add
              ? t1.wordConstVal + t2.wordConstVal
              : t1.wordConstVal - t2.wordConstVal);
    };
    auto byteOp = function (Opcode op, Temp t1, Temp t2) {
      assert(!t1.isWord && !t2.isWord);
      return cast(typeof(Temp.byteConstVal)) (op == Opcode.Add
                                              ? t1.byteConstVal + t2.byteConstVal
                                              : t1.byteConstVal - t2.byteConstVal);
    };

    // This is indirectly a form of constant propagation; we're changing the
    // Temp in-place and its use sites will see the changes.
    if (inst.srcs[0].isConst && inst.srcs[1].isConst) {
      inst.dest.isConst = true;
      assert(inst.srcs[0].isWord == inst.srcs[1].isWord);
      if (inst.srcs[0].isWord) {
        inst.dest.wordConstVal = wordOp(inst.opcode, inst.srcs[0], inst.srcs[1]);
      } else {
        inst.dest.byteConstVal = byteOp(inst.opcode, inst.srcs[0], inst.srcs[1]);
      }
      // Maintain the invariant that all dests are non-const
      b.nopOut(i);
      changed = true;
      continue;
    }

    // Right operand const implies left operand non-const. IR invariant.
    assert(inst.srcs[1].isConst || !inst.srcs[0].isConst);

    if (inst.srcs[1].isConst) {
      Instr prev = inst.srcs[0].inst;
      if (prev.opcode != Opcode.Add && prev.opcode != Opcode.Sub) {
        continue;
      }
      // (x + A) + B --> x + (A + B)
      // (x + A) - B --> x + (A - B)
      // (x - A) + B --> x - (A - B)
      // (x - A) - B --> x - (A + B)
      if (!prev.srcs[1].isConst) {
        continue;
      }

      auto foldOp = (prev.opcode != inst.opcode ? Opcode.Sub : Opcode.Add);
      auto foldedOp = prev.opcode;
      if (inst.srcs[0].isWord) {
        inst.srcs[1].wordConstVal = wordOp(foldOp, prev.srcs[1], inst.srcs[1]);
      } else {
        inst.srcs[1].byteConstVal = byteOp(foldOp, prev.srcs[1], inst.srcs[1]);
      }
      inst.opcode = foldedOp;
      inst.srcs[0] = prev.srcs[0];
      changed = true;
      // This will result in dead code. Leave it to DCE to remove.
    }
    // If we get here, both operands are non-const -- can't do anything.
  }

  return changed;
}

void optimizeConstants(BasicBlock b) {
  bool folded = true;

  // Iterate until convergence.
  while (folded) {
    folded = constantFold(b);
  }
}
