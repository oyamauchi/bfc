/**
 * x86 codegen. Outputs assembly, which you then have to assemble yourself.
 */

import ir;
import regalloc;

import std.container;
import std.conv;
import std.string;
import std.outbuffer;
import std.traits;

import std.stdio;

string[2] codegenIntroOutro() {
  OutBuffer buf = new OutBuffer();
  OutBuffer outroBuf = new OutBuffer();

  // Setup the environment: push registers, setup memory
  buf.write(".globl _main\n");
  buf.write("_main:\n");
  buf.write("  pushq %rbp\n");

  SList!string calleeSavedPops;
  foreach (reg; EnumMembers!Reg) {
    if (!regIsCallerSaved(reg)) {
      buf.write("  pushq %" ~ to!string(reg) ~ "\n");
      calleeSavedPops.insertFront(to!string(reg));
    }
  }


  buf.write("  pushq %" ~ memBaseReg ~ "\n");
  buf.write("  mov $1, %rsi\n");
  buf.write("  mov $30000, %rdi\n");
  buf.write("  call _calloc\n");
  buf.write("  mov %rax, %" ~ memBaseReg ~ "\n");

  outroBuf.write("Lend:\n");
  outroBuf.write("  popq %" ~ memBaseReg ~ "\n");
  foreach (regName; calleeSavedPops) {
    outroBuf.write("  popq %" ~ regName ~ "\n");
  }

  outroBuf.write("  popq %rbp\n");
  outroBuf.write("  xor %rax, %rax\n");
  outroBuf.write("  retq\n");

  return [buf.toString(), outroBuf.toString()];
}

void codegenBlock(BasicBlock b, RegMap regMap, ref OutBuffer buf) {
  auto codegenTemp = delegate(Temp* t) {
    if (t.isConst) {
      if (t.isWord) {
        return format("$%d", t.wordConstVal);
      } else {
        return format("$%d", t.byteConstVal);
      }
    } else {
      if (t.isWord) {
        return format("%%%s", to!string(regMap[t]));
      } else {
        return format("%%%s", byteRegName(regMap[t]));
      }
    }
  };

  auto codegenAddress = delegate(Temp *t) {
    if (t.isConst) {
      return format("%d(%%%s)", t.wordConstVal, memBaseReg);
    } else {
      return format("(%%%s, %%%s)", to!string(regMap[t]), memBaseReg);
    }
  };

  // Used for the short jump after the call to getchar
  int shortLabel = 0;

  buf.write(format("L%d:\n", b.id));

  foreach (ulong idx; 0..b.instrs.length) {
    Instr inst = b.instrs[idx];
    final switch (inst.opcode) {
      case Opcode.Load:
        assert(inst.srcs[0].isWord);
        assert(!inst.dest.isWord);
        auto destReg = regMap[inst.dest];
        buf.write(format("  movb %s, %s\n",
                         codegenAddress(inst.srcs[0]),
                         codegenTemp(inst.dest)));
        break;

      case Opcode.Store:
        assert(inst.srcs[0].isWord);
        assert(!inst.srcs[1].isWord);
        buf.write(format("  movb %s, %s\n",
                         codegenTemp(inst.srcs[1]),
                         codegenAddress(inst.srcs[0])));
        break;

      case Opcode.Add:
        if (inst.srcs[0].isConst && inst.srcs[1].isConst) {
          string op = (inst.dest.isWord ? "movq" : "movb");
          // sketchtown size treatment here
          buf.write(format("  %s $%d, %s\n", op,
                           inst.srcs[0].wordConstVal + inst.srcs[1].wordConstVal,
                           codegenTemp(inst.dest)));
        } else if (inst.srcs[1].isConst) {
          // XXX this doesn't deal with the reverse case
          auto destReg = regMap[inst.dest];
          auto srcReg = regMap[inst.srcs[0]];
          if (destReg == srcReg) {
            string op = (inst.dest.isWord ? "addq" : "addb");
            buf.write(format("  %s %s, %s\n", op,
                             codegenTemp(inst.srcs[1]),
                             codegenTemp(inst.dest)));
          } else {
            assert(false);
            buf.write(format("  leaq %s(%s), %s\n",
                             codegenTemp(inst.srcs[1]),
                             codegenTemp(inst.srcs[0]),
                             codegenTemp(inst.dest)));
          }
        } else {
          assert(false);
          auto destReg = regMap[inst.dest];
          auto src0Reg = regMap[inst.srcs[0]];
          auto src1Reg = regMap[inst.srcs[1]];
          if (destReg == src0Reg) {
            buf.write(format("  addb %s, %s\n",
                             codegenTemp(inst.srcs[1]),
                             codegenTemp(inst.dest)));
          } else if (destReg == src1Reg) {
            buf.write(format("  addb %s, %s\n",
                             codegenTemp(inst.srcs[0]),
                             codegenTemp(inst.dest)));
          } else {
            buf.write(format("  leaq (%s,%s), %s\n",
                             codegenTemp(inst.srcs[0]),
                             codegenTemp(inst.srcs[1]),
                             codegenTemp(inst.dest)));
          }
        }
        break;

      case Opcode.Sub:
        assert(inst.srcs[1].isConst);
        assert(!inst.srcs[0].isConst);
        auto destReg = regMap[inst.dest];
        auto srcReg = regMap[inst.srcs[0]];
        if (destReg == srcReg) {
          string op = (inst.dest.isWord ? "subq" : "subb");
          buf.write(format("  %s %s, %s\n", op,
                           codegenTemp(inst.srcs[1]),
                           codegenTemp(inst.dest)));
        } else {
          assert(false);
        }
        break;

      case Opcode.Putchar:
        // We're gonna need some worrying about register-saving here
        buf.write(format("  movzbl %s, %%edi\n",
                         codegenTemp(inst.srcs[0])));
        buf.write("  call _putchar\n");
        break;
      case Opcode.Getchar:
        buf.write("  call _getchar\n");
        buf.write("  cmpl $0xffffffff, %eax\n");
        buf.write(format("  je LS%d\n", shortLabel));
        buf.write(format("  movb %%al, %s\n", codegenTemp(inst.dest)));
        buf.write(format("LS%d:\n", shortLabel));
        shortLabel++;
        break;
      case Opcode.JumpZ:
      case Opcode.JumpNZ:
        string op = (inst.opcode == Opcode.JumpZ ? "jz" : "jnz");
        buf.write(format("  movb %s, %%r10b\n", codegenTemp(inst.srcs[0])));
        buf.write(       "  test %r10b, %r10b\n");
        buf.write(format("  movq %s, %%r10\n", codegenTemp(b.ptrAtExit)));
        buf.write(format("  %s L%d\n", op, b.successors[1].id));
        buf.write(format("  jmp L%d\n", b.successors[0].id));
        break;

      case Opcode.Merge:
        buf.write(format("  movq %%r10, %s\n", codegenTemp(inst.dest)));
        break;

      case Opcode.Nop:
        // harp darp
        break;
    }
  }

  if (!b.successors[0]) {
    buf.write("  jmp Lend\n");
  }
}
