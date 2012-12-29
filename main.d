
import codegen;
import ir;

import std.container;
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

int main(string[] argv) {
  bool outputC = false;
  getopt(argv,
      "c", &outputC
      );

  if (argv.length != 2) {
    writefln("Usage: %s [flags] <file.bf>", argv[0]);
    writeln("Flags:");
    writeln("  --c    Output C code instead of assembly");
    return 0;
  }

  string filename = argv[1];
  string source = cast(string) read(filename);
  OutBuffer buf = new OutBuffer();

  if (outputC) {
    codegenC(source, buf);
    write(buf.toString());
    return 0;
  }

  Array!Instruction instrs = parse(source);
  codegenInstructions(instrs, buf);
  write(buf.toString());

  return 0;
}

