/**
 * Definition of a basic block, plus functions to decompose a flat program into
 * a CFG of linked basic blocks.
 */
module optimize.cfg;
import ir;

import std.container;

alias BasicBlock[ulong] OffsetToBBMap;

/**
 * A basic block in the classical sense of a single-entry, single-exit sequence
 * of instructions. The last instruction in a BB is always a jump.
 */
class BasicBlock {
  ulong id;
  Array!Instr instrs;
  Array!ulong successors;
  Array!ulong predecessors;

  // Holds a mapping of register numbers to constant values at the end of this
  // basic block.
  int[int] regnumToVal;

  /**
   * Create a map from offsets (in the given instruction stream) to BBs.
   *
   * We're exploiting the property that every jump is to the instruction
   * immediately after another jump instruction. This means we only need to cut
   * off BBs at jump instructions, without worrying about mid-BB entries.
   */
  static OffsetToBBMap createBBMap(Array!Instr instrs) {
    OffsetToBBMap result;

    BasicBlock curr = new BasicBlock();
    curr.id = 0;
    foreach (ulong idx; 0..instrs.length) {
      curr.instrs.insertBack(instrs[idx]);

      Opcode op = instrs[idx].opcode;
      if (op == Opcode.JumpZ || op == Opcode.JumpNZ) {
        curr.successors.insertBack(instrs[idx].jumpNotTaken);
        curr.successors.insertBack(instrs[idx].jumpTaken);
        result[curr.id] = curr;

        curr = new BasicBlock();
        curr.id = idx + 1;
      }
    }

    // Last block
    result[curr.id] = curr;

    /*
    // Compute predecessors, now that the forward CFG is complete
    foreach (BasicBlock bb; result) {
      foreach (ulong succ; bb.successors) {
        result[succ].predecessors.insertBack(bb.id);
      }
    }
    */
    return result;
  }
}
