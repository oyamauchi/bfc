#!/bin/bash

FILE=$1
shift

./bfc $@ --output=x86 test/${FILE}.bf > hello.s
gcc -o hello hello.s
