: $ /assembler -felf64 /assembly.s -o /program.o

nasm -felf64 solver_x86.asm -o solver_x86.obj

gcc solver_x86.obj -o solver_x86.exe

solver_x86.exe


PAUSE

EXIT