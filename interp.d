/**
 * Single-pass interpreter
 *
 * This is a single-pass interpreter for Brainfuck. It's independent of the
 * rest of the system, and mostly used as a reference implementation.
 *
 * Behavioral traits of note:
 *
 * - 30,000 1-byte memory cells.
 * - For ',' input, leaves memory cells untouched on EOF.
 */

import std.file;
import std.stdio;
import std.c.stdio;

void exec_string(string code) {
  char memory[30000];
  foreach (int i; 0..memory.length) {
    memory[i] = 0;
  }

  ulong idx = 0;
  ulong ip = 0;

  while (ip < code.length) {
    switch (code[ip]) {
    case '>':
      idx++; break;
    case '<':
      idx--; break;
    case '+':
      memory[idx]++; break;
    case '-':
      memory[idx]--; break;
    case '.':
      writef("%c", memory[idx]); break;
    case ',':
      int ch = getchar();
      if (ch != -1) {
        memory[idx] = cast(char) ch;
      }
      break;
    case '[':
      if (!memory[idx]) {
        int brack_count = 1;
        do {
          ip++;
          if (code[ip] == '[') {
            brack_count++;
          } else if (code[ip] == ']') {
            brack_count--;
          }
        } while (brack_count > 0);
      }
      break;

    case ']':
      if (memory[idx]) {
        int brack_count = 1;
        do {
          ip--;
          if (code[ip] == ']') {
            brack_count++;
          } else if (code[ip] == '[') {
            brack_count--;
          }
        } while (brack_count > 0);
      }
      break;

    default:
      // meh
    }

    ip++;
  }

}

void main(string argv[]) {
  if (argv.length != 2) {
    writefln("Usage: %s <file.bf>", argv[0]);
  }

  exec_string(cast(string) read(argv[1]));
}
