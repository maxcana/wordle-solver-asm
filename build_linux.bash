#!/bin/bash

# clean
rm -rf ./compile/linux
mkdir -p ./compile/linux

# assemble
nasm -f elf64 solver_x86.asm -o compile/linux/solver_x86.o
nasm -f elf64 helper.asm -o compile/linux/helper.o

# link
gcc -no-pie -o compile/linux/solver_x86 compile/linux/solver_x86.o compile/linux/helper.o

# run
./compile/linux/solver_x86