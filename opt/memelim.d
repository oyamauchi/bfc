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
  Temp[typeof(Temp.tempNum)] replaceMap;
  // Pretty sure these could be the same map but I'm not good enough at D
  Temp[typeof(Temp.wordConstVal)] savedConstStores; // maps address to value
  Temp[typeof(Temp.tempNum)] savedVarStores; // maps temp number to value

  foreach (i; 0..b.instrs.length) {
    auto inst = b.instrs[i];
    // Now just do all the replacements.
    foreach (j; 0..inst.srcs.length) {
      auto mapEntry = inst.srcs[j].tempNum in replaceMap;
      if (mapEntry) {
        inst.srcs[j] = *mapEntry;
      }
    }

    // If we see a store, update our idea of what's been stored where.
    if (inst.opcode == Opcode.Store) {
      auto addr = inst.srcs[0];
      if (addr.isConst) {
        savedConstStores[addr.wordConstVal] = inst.srcs[1];
      } else {
        savedConstStores.clear();
        savedVarStores[addr.tempNum] = inst.srcs[1];
      }
    }

    if (inst.opcode == Opcode.Load) {
      auto addr = inst.srcs[0];
      if (addr.isConst) {
        auto replacement = addr.wordConstVal in savedConstStores;
        if (replacement) {
          replaceMap[inst.dest.tempNum] = *replacement;
          b.nopOut(i);
        }
      } else {
        auto replacement = addr.tempNum in savedVarStores;
        if (replacement) {
          replaceMap[inst.dest.tempNum] = *replacement;
          b.nopOut(i);
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
  bool[typeof(Temp.wordConstVal)] overwriteConstMap;
  // Maps temp number to temp later stored there.
  bool[typeof(Temp.tempNum)] overwriteVarMap;

  // Overflow, jesus.
  for (ulong i = b.instrs.length - 1; i < b.instrs.length; --i) {
    auto inst = b.instrs[i];
    if (inst.opcode == Opcode.Store) {
      if (inst.srcs[0].isConst) {
        // Is this going to get overwritten later?
        if (inst.srcs[0].wordConstVal in overwriteConstMap) {
          // Eliminate this one.
          b.nopOut(i);
        } else {
          // This one will take over.
          overwriteConstMap[inst.srcs[0].wordConstVal] = true;
        }
      } else {
        if (inst.srcs[0].tempNum in overwriteVarMap) {
          b.nopOut(i);
        } else {
          overwriteConstMap.clear();
          overwriteVarMap[inst.srcs[0].tempNum] = true;
        }
      }
    }

    if (inst.opcode == Opcode.Load) {
      // Going backward from here, stores to this address are no longer redundant.
      if (inst.srcs[0].isConst) {
        overwriteConstMap.remove(inst.srcs[0].wordConstVal);
      } else {
        overwriteVarMap.remove(inst.srcs[0].tempNum);
      }
    }
  }
}
