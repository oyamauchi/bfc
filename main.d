
import codegen;
import ir;

import std.container;
import std.outbuffer;
import std.file;
import std.stdio;

int main(string[] argv) {
  if (argv.length != 2) {
    writefln("Usage: %s <file.bf>", argv[0]);
    return 0;
  }

  string filename = argv[1];
  string source = cast(string) read(filename);

  Array!Instruction instrs = parse(source);

  OutBuffer buf = new OutBuffer();
  codegenInstructions(instrs, buf);
  write(buf.toString());

  return 0;
}

