/**
 * Dead code elimination. Really simple.
 */

module opt.dce;

import ir;

void eliminateDeadCode(BasicBlock b) {
  bool[Temp*] usedSet;

  foreach (inst; b.instrs) {
    foreach (src; inst.srcs) {
      usedSet[src] = true;
    }
  }

  // Use a plain for loop here because we mess with the index
  for (ulong i = 0; i < b.instrs.length; ++i) {
    auto dest = b.instrs[i].dest;
    auto destIsUnused = (dest && !(dest in usedSet));
    if (b.instrs[i].opcode == Opcode.Nop || destIsUnused) {
      b.instrs.linearRemove(b.instrs[i..i+1]);
      i--;  // so we process this index again
    }
  }
}
