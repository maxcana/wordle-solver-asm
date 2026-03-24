; printing and debugging utility wrappers
default rel
section .text
; exports
    global safe_print_bitmap
    global print_bitmap
    global safe_print_word
    global print_word
    global print
    global win64_exit
    global linux_exit

; windows api stuff
    extern GetStdHandle
    extern WriteFile
    extern ExitProcess


safe_print_bitmap:
  push rax
  push rbx
  push rcx
  push rdx
  push rsi
  push rdi
  push rbp
  push r8
  push r9
  push r10
  push r11
  push r12
  push r13
  push r14
  push r15
  ; save xmm registers from syscall/windows api
  sub rsp, 16
  movdqu [rsp], xmm0
  sub rsp, 16
  movdqu [rsp], xmm1
  sub rsp, 16
  movdqu [rsp], xmm2

  call print_bitmap

  ; preserved xmm registers
  movdqu xmm2, [rsp]
  add rsp, 16
  movdqu xmm1, [rsp]
  add rsp, 16
  movdqu xmm0, [rsp]
  add rsp, 16
  pop r15
  pop r14
  pop r13
  pop r12
  pop r11
  pop r10
  pop r9
  pop r8
  pop rbp
  pop rdi
  pop rsi
  pop rdx
  pop rcx
  pop rbx
  pop rax 
  ret

; modifies: xmm3, r14, r10, rsi, rdi, everything that system modifies
print_bitmap:

  ; first, write the string backwards  onto the stack
  push rbp

  mov rbp, rsp ; copy rsp to rbp, which we will decrement and use to write each character
  ; im not even using rsp for stack modification isnt that crazy
  ; rsp will stay at the bottom of the allocated space (396 characters) while rbp moves and writes backwards (done to allow calling subroutines)
  sub rsp, 397


  dec rbp
  mov [rbp], byte 0xA ; end of string

  ; first newline should be after 286 bits
  ; we start at bit 384, so 98 bits before the first newline
  ; 1026-98 = 928
  mov rdi, 928 ; 26-checker (add carriage return + line feed every 26) (starts at 1000 because we want it to go through the unused bits before actually printing newlines)

  movdqu xmm3, xmm2

  movq r14, xmm3 ; move low 64 bits into register
  call .append_bits
  pextrq r14, xmm3, 1 ; move high 64 bits into register
  call .append_bits
  
  movdqu xmm3, xmm1

  movq r14, xmm3
  call .append_bits
  pextrq r14, xmm3, 1
  call .append_bits

  movdqu xmm3, xmm0

  movq r14, xmm3
  call .append_bits
  pextrq r14, xmm3, 1
  call .append_bits

  mov rsi, rbp
  mov rdi, 397 ; print 384 characters + 12 line feeds + 1 null terminator

  call print

  add rsp, 397 ; fix the stack

  pop rbp

  ret

  .append_bits: ; add 64 bits
    mov rsi, 64 ; counter

    .loop_begin:
      mov r10b, r14b
      and r10b, 0b00000001 ; find the 0 or 1
      add r10b, "0" ; write a byte with the character into the stack

      dec rbp
      mov [rbp], r10b

      shr r14, 1

      inc rdi
      cmp rdi, 1026
      jne .isnt ; if we want a newline on the bitmap (every 26 characters, but delayed at the beginning)

      mov rdi, 1000 ; reset the 26-counter
      
      dec rbp
      mov [rbp], byte 0xA ; line feed

      .isnt: ; endif

      dec rsi
      test rsi,rsi
      jne .loop_begin
    ret


safe_print_word:
  push rax
  push rbx
  push rcx
  push rdx
  push rsi
  push rdi
  push rbp
  push r8
  push r9
  push r10
  push r11
  push r12
  push r13
  push r14
  push r15
  ; save xmm registers from syscall/windows api
  sub rsp, 16
  movdqu [rsp], xmm0
  sub rsp, 16
  movdqu [rsp], xmm1
  sub rsp, 16
  movdqu [rsp], xmm2

  call print_word

  ; preserved xmm registers
  movdqu xmm2, [rsp]
  add rsp, 16
  movdqu xmm1, [rsp]
  add rsp, 16
  movdqu xmm0, [rsp]
  add rsp, 16
  pop r15
  pop r14
  pop r13
  pop r12
  pop r11
  pop r10
  pop r9
  pop r8
  pop rbp
  pop rdi
  pop rsi
  pop rdx
  pop rcx
  pop rbx
  pop rax 
  ret

; rsi - word in the form 00 00 00 00 00 07 04 03
; modifies: caller-saved registers, rsi, rdi, r8
print_word:
  mov r8, 5
  mov rdi, 0x6161616161616161
  add rsi, rdi
  loop:
  ; sil = letter
  dec rsp
  mov byte [rsp], sil
  shr rsi, 8
  dec r8
  jne loop

  mov rsi, rsp
  mov rdi, 5
  ; push 11 more bytes to keep stack 16-byte aligned for call
  sub rsp, 11

  ; now we have the stack as ...........AAHED
  call print
  add rsp, 16

; wrapper print function
; rsi - Pointer to the string to print
; rdi - Length of the string
; preserves: everything
; Return: None
print:
  push rax
  push rbx
  push rcx
  push rdx
  push rsi
  push rdi
  push rbp
  push r8
  push r9
  push r10
  push r11
  push r12
  push r13
  push r14
  push r15
  ; save xmm registers from syscall/windows api
  sub rsp, 16
  movdqu [rsp], xmm0
  sub rsp, 16
  movdqu [rsp], xmm1
  sub rsp, 16
  movdqu [rsp], xmm2

  call win64_print

  movdqu xmm2, [rsp]
  add rsp, 16
  movdqu xmm1, [rsp]
  add rsp, 16
  movdqu xmm0, [rsp]
  add rsp, 16
  pop r15
  pop r14
  pop r13
  pop r12
  pop r11
  pop r10
  pop r9
  pop r8
  pop rbp
  pop rdi
  pop rsi
  pop rdx
  pop rcx
  pop rbx
  pop rax
  ret

; rsi - Pointer to the string to print
; rdi - Length of the string
; Return: None
linux_print:
  push rbp
  mov rbp, rsp
  mov rax, 1
  mov rdx, rdi
  mov rdi, 1
  ; rdi - File descriptor (1 for stdout)
  ; rsi - Pointer to the string to print
  ; rdx - Length of the string
  syscall
  pop rbp
  ret

; rdi - Exit code
; Return: None
linux_exit:
  push rbp
  mov rbp, rsp
  mov rax, 60
  syscall
  pop rbp
  ret

; rsi - Pointer to the string to print
; rdi - Length of the string
; modifies: rcx, rdx, rax, r8, r9
; Return: None
win64_print:
  sub rsp, 48 ; [32 shadow ... 8 local ... 8 unused, for alignment]

  ; GetStdHandle(STD_OUTPUT_HANDLE)
  mov rcx, -11
  call GetStdHandle

  ; Prepare WriteFile
  mov rcx, rax ; hFile
  mov rdx, rsi ; lpBuffer
  mov r8, rdi ; nBytesToWrite
  lea r9, [rsp+32] ; lpBytesWritten (ptr to local variable)
  mov qword [rsp+32], 0 ; clear bytes 32-39 (lpBytesWritten)

  mov qword [rsp+24], 0 ; 5th param (lpOverlapped)

  call WriteFile

  add rsp, 48
  ret

win64_exit:
  ; ExitProcess(0)
  xor rcx,rcx
  call ExitProcess
  hlt

