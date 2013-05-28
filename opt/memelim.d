/**
 * Eliminates redundant loads and stores.
 *
 * A load is redundant if we can definitively find the last store to that
 * address; we replace the result of the load with the last value that was
 * stored there. A store is redundant if we can prove that another store to the
 * same address will happen later, before any loads from that location.
 *
 * This means we can only eliminate loads and stores to constant addresses. It
 * also means that you should eliminate loads first, then stores. Redundant
 * stores are much easier to identify in the absence of intervening loads.
 */
module opt.memelim;

import ir;

/**
 * Replace the dests of loads with the src to the corresponding store, if known.
 */
void eliminateRedundantLoads(BasicBlock b) {
  Temp*[Temp*] replaceMap;
  Temp*[ulong] savedStores;

  foreach (inst; b.instrs) {
    // Now just do all the replacements.
    foreach (i; 0..inst.srcs.length) {
      auto mapEntry = inst.srcs[i] in replaceMap;
      if (mapEntry) {
        inst.srcs[i] = *mapEntry;
      }
    }

    // If we see a store, update our idea of what's been stored where.
    if (inst.opcode == Opcode.Store) {
      auto addr = inst.srcs[0];
      if (addr.isConst) {
        savedStores[addr.tmpNum] = inst.srcs[1];
      } else {
        // If the store is to a variable address, we're hosed; it could have
        // been to anywhere, so we have to forget all we know.
        savedStores.clear();
      }
    }

    if (inst.opcode == Opcode.Load) {
      auto addr = inst.srcs[0];
      if (addr.isConst) {
        auto replacement = addr.tmpNum in savedStores;
        if (replacement) {
          replaceMap[inst.dest] = *replacement;
        }
      }
    }
  }
}

/**
 * Iterate backwards through the block. If we come across a store to a location
 * that is stored to later in the block, with no intervening loads from that
 * location or variable loads or stores, the earlier store can be eliminated.
 */
void eliminateRedundantStores(BasicBlock b) {
  // Maps memory address to temp later stored there.
  bool[ulong] overwrittenLater;

  // Overflow, jesus.
  for (ulong i = b.instrs.length - 1; i < b.instrs.length; --i) {
    auto inst = b.instrs[i];
    if (inst.opcode == Opcode.Store) {
      if (inst.srcs[0].isConst) {
        // Is this going to get overwritten later?
        if (inst.srcs[0].tmpNum in overwrittenLater) {
          // Eliminate this one.
          Instr newInst = Instr(Opcode.Nop, null, []);
          b.instrs[i] = newInst;
        } else {
          // This one will take over.
          overwrittenLater[inst.srcs[0].tmpNum] = true;
        }
      } else {
        // Variable store. We have to forget everything.
        overwrittenLater.clear();
      }
    }

    if (inst.opcode == Opcode.Load) {
      if (inst.srcs[0].isConst) {
        // XXX Gotta do this, man. Doesn't matter now because we always remove
        // loads first.
        //        overwrittenLater.remove(inst.srcs[0].tmpNum);
      } else {
        // Variable load. No screwing around with memory before this.
        overwrittenLater.clear();
      }
    }
  }
}
