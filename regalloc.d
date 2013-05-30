/**
 * A simple linear-scan register allocator for x86-64.
 */

import ir;

import std.traits;

// These are best callee-saved.
immutable string memBaseReg = "r15";

enum Reg {
  rbx,
  //  r10, scratch
  r11,
  r12,
  r13,
  r14,
  rax,
  rcx,
  rdx,
  rsi,
  rdi,
  r8,
  r9,
  // r15 reserved
}

// A LiveRange's start is the instruction where it's first assigned. The end is
// the last instruction where it's used.
alias long[2] LiveRange;
alias LiveRange[Temp*] LiveRangeMap;
alias Reg[Temp*] RegMap;

LiveRangeMap computeLiveRanges(BasicBlock b) {
  LiveRangeMap map;

  foreach (i; 0..b.instrs.length) {
    // Since this is in SSA form, every temp we see as a dest must be the first
    // appearance as a dest, and therefore the start of its live range.
    auto inst = b.instrs[i];
    if (opcodeHasDest(inst.opcode)) {
      assert(!(inst.dest in map));
      assert(!inst.dest.isConst);
      map[inst.dest] = [cast(long) i, -1];
    }

    foreach (src; inst.srcs) {
      if (src.isConst) {
        continue;
      }

      map[src][1] = cast(long) i;
    }
  }

  if (b.ptrAtExit && !b.ptrAtExit.isConst) {
    map[b.ptrAtExit][1] = b.instrs.length;
  }

  return map;
}

/*
private Array!(Temp*) regsLiveAt(ulong offset, LiveRangeMap liveRanges) {
  Array!(Temp*) result;

  foreach (temp; liveRanges.keys) {
    LiveRange range = liveRanges[temp];
    if (range[0] <= offset && range[1] > offset) {
      result.insertBack(temp);
    }
  }

  return result;
}
*/

RegMap allocateRegs(BasicBlock b, LiveRangeMap liveRanges) {
  RegMap map;
  bool[Reg] allocated;
  immutable order = [ EnumMembers!Reg ];

  foreach (reg; order) {
    allocated[reg] = false;
  }

  auto pick = delegate() {
    foreach (reg; order) {
      if (!allocated[reg]) {
        return reg;
      }
    }
    // Oh balls we're out of registers
    assert(false);
  };

  foreach (i; 0..b.instrs.length) {
    // Every temp's live range ends at an instruction where the temp is used.
    // Check if any of this instruction's sources are dying here, and free its
    // register if so. The dest may end up getting allocated to the same reg as
    // one of the srcs, but that's fine.
    foreach (src; b.instrs[i].srcs) {
      if (src.isConst) {
        continue;
      }
      if (liveRanges[src][1] == i) {
        allocated[map[src]] = false;
      }
    }

    if (opcodeHasDest(b.instrs[i].opcode)) {
      auto reg = pick();
      assert(!allocated[reg]);
      map[b.instrs[i].dest] = reg;
      allocated[reg] = true;
    }
  }

  return map;
}

string byteRegName(Reg r) {
  final switch (r) {
    case Reg.rax: return "al";
    case Reg.rbx: return "bl";
    case Reg.rcx: return "cl";
    case Reg.rdx: return "dl";
    case Reg.rsi: return "sil";
    case Reg.rdi: return "dil";
    case Reg.r8:  return "r8b";
    case Reg.r9:  return "r9b";
    case Reg.r11: return "r11b";
    case Reg.r12: return "r12b";
    case Reg.r13: return "r13b";
    case Reg.r14: return "r14b";
  }
}

bool regIsCallerSaved(Reg r) {
  switch (r) {
    case Reg.rax:
    case Reg.rcx:
    case Reg.rdx:
    case Reg.rsi:
    case Reg.rdi:
    case Reg.r8:
    case Reg.r9:
      return true;
    default:
      return false;
  }
}
