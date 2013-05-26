
import codegen;
import ir;
import optimize.cfg;

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
}

int main(string[] argv) {
  OutputFormat outputFormat = OutputFormat.x86;
  try {
    getopt(argv,
        "output", &outputFormat
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

  Array!Instr instrs = parse(source);
  OffsetToBBMap map = BasicBlock.createBBMap(instrs);

  if (outputFormat == OutputFormat.ir) {
    foreach (ulong id; map.byKey()) {
      OutBuffer bbuf = new OutBuffer();
      writef("%d:\n", id);
      printInstructions(map[id].instrs, bbuf, id);
      write(bbuf.toString());
      write("\n");
    }
    return 0;
  }

  //  codegenInstructions(instrs, buf);
  //  write(buf.toString());

  return 0;
}
