/**
 * Dead code elimination. Really simple.
 */

module opt.dce;

import ir;

void eliminateDeadCode(BasicBlock b) {
  bool changed;

  do {
    changed = false;
    bool[typeof(Temp.tempNum)] usedSet;

    foreach (inst; b.instrs) {
      foreach (src; inst.srcs) {
        if (!src.isConst) {
          usedSet[src.tempNum] = true;
        }
      }
    }

    // Use a plain for loop here because we mess with the index
    for (ulong i = 0; i < b.instrs.length; ++i) {
      auto dest = b.instrs[i].dest;
      assert(!dest || !dest.isConst);

      auto destIsUnused = (dest && !(dest.tempNum in usedSet));
      if (b.instrs[i].opcode == Opcode.Nop || destIsUnused) {
        changed = true;
        b.instrs.linearRemove(b.instrs[i..i + 1]);
        i--;  // process this index again
      }
    }
  } while (changed);
}
