: $ /assembler -felf64 /assembly.s -o /program.o

del solver_x86.obj
del solver_x86.exe

nasm -f win64 solver_x86.asm -o solver_x86.obj

gcc solver_x86.obj -o solver_x86.exe

solver_x86.exe


PAUSE

EXIT