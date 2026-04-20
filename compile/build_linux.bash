#!/bin/bash

# clean
rm -rf ./compile/linux
mkdir -p ./compile/linux

# assemble
OBJS=()
for f in src/**/*.asm src/*.asm; do
    [ -f "$f" ] || continue
    base=$(basename "$f" .asm)
    nasm -f elf64 -DLINUX "$f" -o "compile/linux/${base}.o"
    OBJS+=("compile/linux/${base}.o")
done

# link
gcc -no-pie -o compile/linux/solver_x86 "${OBJS[@]}"

# run
./compile/linux/solver_x86