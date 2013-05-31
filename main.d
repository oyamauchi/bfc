
import codegen;
import ir;
import regalloc;
import opt.constprop;
import opt.dce;
import opt.memelim;

import std.container;
import std.conv;
import std.outbuffer;
import std.file;
import std.getopt;
import std.stdio;

void codegenC(string source, ref OutBuffer buf) {
  buf.write("#include <stdlib.h>\n");
  buf.write("int main() {\n");
  buf.write("char* ptr = calloc(30000, 1);\n");
  buf.write("int getchartmp;\n");
  foreach (ulong i; 0..source.length) {
    switch (source[i]) {
      case '+': buf.write("++*ptr;\n"); break;
      case '-': buf.write("--*ptr;\n"); break;
      case '<': buf.write("--ptr;\n"); break;
      case '>': buf.write("++ptr;\n"); break;
      case '.': buf.write("putchar(*ptr);\n"); break;
      case ',': buf.write("getchartmp = getchar();");
                buf.write("if (getchartmp != -1) *ptr = (char)getchartmp;\n");
                break;
      case '[': buf.write("while (*ptr) {\n"); break;
      case ']': buf.write("}\n"); break;
      default: // meh
    }
  }

  buf.write("return 0;\n");
  buf.write("}\n");
}

enum OutputFormat {
  x86, c, ir
}

void usage(string progname) {
  writefln("Usage: %s [flags] <file.bf>", progname);
  writeln("Flags:");
  writeln("  --output=<format>    'x86' (default), 'c' or 'ir'");
  writeln("  --no-opt             turn optimizations off");
}

int main(string[] argv) {
  OutputFormat outputFormat = OutputFormat.x86;
  bool noOpts = false;
  try {
    getopt(argv,
           "output", &outputFormat,
           "no-opt", &noOpts
        );
  } catch {
    usage(argv[0]);
    return 0;
  }

  if (argv.length != 2) {
    usage(argv[0]);
    return 0;
  }

  string filename = argv[1];
  string source = cast(string) read(filename);
  OutBuffer buf = new OutBuffer();

  if (outputFormat == OutputFormat.c) {
    codegenC(source, buf);
    write(buf.toString());
    return 0;
  }

  Parser p = new Parser(source);
  auto root = p.parse();

    DList!BasicBlock queue;
    bool[ulong] visited;
    OutBuffer bbuf = new OutBuffer();
    queue.insertBack(root);

    while (!queue.empty) {
      auto block = queue.front();
      queue.removeFront();

      if (block.id in visited) {
        continue;
      }
      visited[block.id] = true;

      if (!noOpts) {
        eliminateRedundantLoads(block);
        eliminateRedundantStores(block);
        optimizeConstants(block);
        eliminateDeadCode(block);
      }

      LiveRangeMap liveRanges = computeLiveRanges(block);
      RegMap regs = allocateRegs(block, liveRanges);

      if (outputFormat == OutputFormat.ir) {
        block.print(bbuf);
      } else {
        codegenBlock(block, regs, bbuf);
      }

      if (block.successors[0]) {
        queue.insertBack(block.successors[0]);
      }
      if (block.successors[1]) {
        queue.insertBack(block.successors[1]);
      }
    }

    string introOutro[2] = codegenIntroOutro();
    if (outputFormat == OutputFormat.x86) {
      write(introOutro[0]);
    }
    write(bbuf.toString());
    if (outputFormat == OutputFormat.x86) {
      write(introOutro[1]);
    }

    return 0;
}
