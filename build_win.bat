: $ /assembler -felf64 /assembly.s -o /program.o

: clean
rd /s /q compile\win64
mkdir compile\win64

: assemble
nasm -f win64 solver_x86.asm -o compile\win64\solver_x86.obj
nasm -f win64 helper.asm -o compile\win64\helper.obj

: link
gcc -o compile\win64\solver_x86.exe compile\win64\solver_x86.obj compile\win64\helper.obj

: run
compile\win64\solver_x86.exe


PAUSE

EXIT