
import codegen;
import ir;

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

  auto root = parseBasicBlock(source, 0);

  if (outputFormat == OutputFormat.ir) {
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
      block.print(bbuf);
      if (block.successors[0]) {
        queue.insertBack(block.successors[0]);
      }
      if (block.successors[1]) {
        queue.insertBack(block.successors[1]);
      }
    }

    write(bbuf.toString());
    return 0;
  }

  return 0;
}
