: $ /assembler -felf64 /assembly.s -o /program.o
@ECHO off
SETLOCAL enabledelayedexpansion

: clean
rd /s /q compile\win64
mkdir compile\win64

: assemble
set OBJS=
for /R src %%F in (*.asm) do (
    ECHO Assembling %%F...
    nasm -f win64 -DWINDOWS "%%F" -o "compile\win64\%%~nF.obj"

    set "OBJS=!OBJS! compile\win64\%%~nF.obj"
)

: link
ECHO Linking...
gcc -o compile\win64\solver_x86.exe !OBJS!

: run
ECHO Running...
compile\win64\solver_x86.exe


PAUSE

EXIT