; printing, input handling, debugging utility
; wrappers for linux and windows ABIs
default rel
section .text
; exports
  ; functions
    global safe_print_bitmap
    global safe_print_word
    global print
    global print_newline
    global input
    global yikes
    global exit
    global write_fnumber
    global write_fdouble
    global sort_array

  ; bss
    global input_buffer ; bss data - output of input subroutine
    global sort_output
    

; windows api stuff
%ifdef WINDOWS
  extern GetStdHandle
  extern WriteFile
  extern ExitProcess
  extern ReadFile
%endif

; MARK: Macros

; args: windows_fn, linux_fn
; this decides at assemble time to substitute with the correct platform-specific function
%macro PLATFORM_CALL 2
    %ifdef WINDOWS
        call %1
    %else
        call %2
    %endif
%endmacro

; note: storing this much might be mega slow, so don't print too oftenz
; its like pushaq if it existed, but also pushes xmm0-2 registers
%macro STR_REGS 0
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
%endmacro
%macro LD_REGS 0
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
%endmacro

; MARK: Bitmaps & words
safe_print_bitmap:
  STR_REGS
  call print_bitmap
  LD_REGS
  ret

; modifies: caller-saved registers, xmm3, r14, r10, rsi, rdi
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
  mov rdi, 397 ; print 384 characters + 12 line feeds + 1 more line feed at end

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


; rsi - word in the form 00 00 00 00 00 07 04 03
; preserves: everything
safe_print_word:
  STR_REGS
  call print_word
  LD_REGS
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

; just calls print, passing in newline
; preserves: everything
print_newline:
  STR_REGS
  mov rsi, newline_msg
  mov rdi, newline_len
  call print
  LD_REGS
  ret

; MARK: Wrappers

; wrapper print function
; rsi - Pointer to the string to print
; rdi - Length of the string
; preserves: everything
; Return: None
print:
  STR_REGS
  PLATFORM_CALL win64_print, linux_print
  LD_REGS
  ret

; modifies: caller-saved registers, rcx, rax
; Return: rax - number of bytes user has entered (excluding newline)
; Output: located at [input_buffer]
input:
  ; clear buffer
  lea rdi, [rel input_buffer]
  xor al, al
  mov rcx, 256 ; # bytes to clear
  rep stosb

  PLATFORM_CALL win64_input, linux_input

  ; we do need to output rax
  ret
exit:
  PLATFORM_CALL win64_exit, linux_exit

; MARK: ABI-specific

%ifdef LINUX
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

; Return: rax - number of bytes user has entered (excluding newline)
; location of output - [input_buffer]
linux_input:
  mov rax, 0 ; sys_read
  mov rdi, 0 ; file descriptor stdin
  mov rsi, input_buffer ; address of buffer to store input
  mov rdx, input_buffer_len
  ; Return: rax - number of bytes read
  syscall

  dec rax ; remove \n

  ; null terminate (we really don't need to, but whatever) (doesn't count as part of the length)
  lea rbx, [rel input_buffer]
  mov byte [rbx + rax], 0
  
  ret
%endif

%ifdef WINDOWS
; rsi - Pointer to the string to print
; rdi - Length of the string
; modifies: caller-saved registers, rcx, rdx, rax, r8, r9
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

; Return: rax - number of bytes user has entered (excluding newline)
; location of output - [input_buffer]
win64_input:
  sub rsp, 48 ; [32 shadow ... 8 local ... 8 unused, for alignment]

  ; GetStdHandle(STD_OUTPUT_HANDLE)
  mov rcx, -10
  call GetStdHandle

  mov rcx, rax ; hFile
  lea rdx, [rel input_buffer] ; lpBuffer (output)
  mov r8, input_buffer_len ; nNumberOfBytesToRead
  lea r9, [rel win64_input_num_bytes_read_output] ; lpNumberOfBytesRead (output)
  mov qword [rsp + 32], 0 ; lpOverlapped
  call ReadFile

  mov qword rax, [rel win64_input_num_bytes_read_output] ; move number of bytes output into rax
  sub rax, 2 ; clear \r\n

  ; add null terminator (optional) (don't count as part of the length)
  lea rbx, [rel input_buffer]
  mov byte [rbx + rax], 0

  add rsp, 48
  ret

%endif

; MARK: Random utility

; call when something goes wrong
; preserves: everything
yikes:
  push rsi
  push rdi
  mov rsi, yikes_msg
  mov rdi, yikes_len
  call print
  pop rdi
  pop rsi
  ret

; writes a base 10 number as a (formatted ASCII string) into memory from a number
; rdi - number (u64)
; Return: 
; rdi - length of string (excluding newline)
; rsi - memory location of string
; preserves: everything
write_fnumber:
  mov [temp_qword], rdi
  STR_REGS
  mov rdi, [temp_qword]

  mov rcx, 10 ; divisor for div ecx
  mov rbp, number_buffer
  add rbp, 256
  xor r8,r8

  mov eax, edi
  mov rdx, rdi
  shr rdx, 32
  log_int_loop:
    ; edx = higher 32 bits of dividend
    ; eax = lower 32 bits of dividend
    div ecx ; divisor

    ; rax is 64-bit quotient
    ; rdx is 64-bit remainder
    dec rbp
    add rdx, "0" ; add the ascii value for "0" (0x30)
    mov [rbp], dl ; push remainder (last digit) and replace old value with quotient

    inc r8 ; increase length of string
    
    ; set up for next iteration
    mov rdx, rax
    shr rdx, 32

    cmp eax, 0
    jne log_int_loop

  mov [temp_qword], r8
  mov [temp_qword_2], rbp
  LD_REGS
  mov rdi, [temp_qword]
  mov rsi, [temp_qword_2]
  ret

; writes the result of the division with 2 digits after decimal of precision (floored)
; rsi - divisor i64 (top)
; rdi - dividend i64 (bottom)
; Return:
; rdi - length of string (excluding newline)
; rsi - memory location of string
; modifies: xmm4-6 only
write_fdouble:
  mov [rel temp_qword], rsi
  mov [rel temp_qword_2], rdi
  STR_REGS
  mov rsi, [rel temp_qword]
  mov rdi, [rel temp_qword_2]

  ; note: high 64 bits of xmm register is unused for double (f64)
  cvtsi2sd xmm4, rsi
  cvtsi2sd xmm5, rdi
  divsd xmm4, xmm5 ; xmm4 = xmm4/xmm5
  ; we are NOT using the C library printf (anything but the C library)

  ; example: xmm4 = 48923560.454389
  cvttsd2si rax, xmm4 ; rax = 48923560
  cvtsi2sd xmm5, rax ; xmm5 = 48923560
  subsd xmm4, xmm5 ; xmm4 = 0.454389
  
  mov r9, 1000 ; temp r9 (10^3 = 3 digits after decimal)
  cvtsi2sd xmm6, rax
  mulsd xmm4, xmm6 ; xmm4 = 454.3
  cvttsd2si rbx, xmm4 ; rbx = 454

  ; now to write the string into the buffer
  mov rdi, rax
  call write_fnumber

  ; copy to stack
  ; rsi = src, rdi = dest, rcx = count
  mov rcx, rdi ; count
  lea rdi, [rel double_buffer] ; dest
  cld
  rep movsq
  add rdi, rcx

  ; write the period
  mov byte [rdi], '.'
  inc rdi
  mov rbp, rdi

  mov rdi, rbx
  call write_fnumber

  ; copy to stack again
  mov rcx, rdi ; count
  mov rdi, rbp ; dest
  cld
  rep movsq
  add rbp, rcx

  ; outputs
  mov rdi, rbp
  lea rax, [rel double_buffer]
  sub rdi, rax ; rdi = length

  mov [rel temp_qword], rdi
  LD_REGS
  lea rsi, [rel double_buffer]
  mov rdi, [rel temp_qword]
  ret
  


; MARK: Radix sorter

; radix sorter
; outputs: array of words length rdi located at [sort_output]: indexes corresponding to values on the original array (from unsigned highest to lowest)
; rsi - pointer to array of qwords
; rdi - length of array (maximum 14855)
; preserves: everything
; [(most of this) FUNCTION IS NOT WRITTEN BY ME]
sort_array:
  mov [rel temp_qword], rsi
  mov [rel temp_qword_2], rdi
  STR_REGS
  ; r12 = input array ptr, r13 = length
  mov r12, [rel temp_qword]
  mov r13, [rel temp_qword_2]
  lea r9, [rel sort_output] ; r9 permanently set to sort_output (for this function)

  ; init sort_output with identity [0, 1, ..., n-1] as words
  lea rdi, [rel sort_output]
  xor ecx, ecx
  .init_loop:
      cmp ecx, r13d
      jge .init_done
      mov [rdi + rcx*2], cx
      inc ecx
      jmp .init_loop
  .init_done:
      ; 8 passes, LSB first
      ; src always = sort_output (we scatter into stack buf, copy back)
      ; this avoids needing a second resw buffer
      xor r14, r14 ; pass index

  .pass_loop:
      cmp r14, 8
      jge .pass_done

      mov rcx, r14
      shl rcx, 3 ; shift = pass * 8

      ; count[256] on stack, zero it
      sub rsp, 256*8
      mov rdi, rsp
      xor eax, eax
      mov r15, 256
  .zero_loop:
      mov [rdi + r15*8 - 8], rax
      dec r15
      jnz .zero_loop

      ; --- count ---
      xor r15, r15
  .count_loop:
      cmp r15, r13
      jge .count_done
      movzx rdx, word [r9 + r15*2] ; index (word)
      mov rdx, [r12 + rdx*8] ; value
      mov rbx, rdx
      shr rbx, cl ; cl = shift
      and rbx, 0xFF
      inc qword [rsp + rbx*8]
      inc r15
      jmp .count_loop
  .count_done:

      ; --- exclusive prefix sum ---
      xor r15, r15
      xor rbp, rbp
  .scan_loop:
      cmp r15, 256
      jge .scan_done
      mov rdx, [rsp + r15*8]
      mov [rsp + r15*8], rbp
      add rbp, rdx
      inc r15
      jmp .scan_loop
  .scan_done:
      ; scatter into temp_buf on stack (above count[])
      ; we need n words of scratch. allocate on stack
      ; n <= 14855, so 14855*2 = 29710 bytes, round to 29712
      sub rsp, 29712
      ; layout: rsp+0 = word scratch buf, rsp+29712 = count[256] qwords
      xor r15, r15
  .scatter_loop:
      cmp r15, r13
      jge .scatter_done
      
      movzx rdx, word [r9 + r15*2] ; index
      mov rax, [r12 + rdx*8] ; value
      mov rbx, rax
      shr rbx, cl
      and rbx, 0xFF
      mov rdi, [rsp + 29712 + rbx*8] ; position
      inc qword [rsp + 29712 + rbx*8]
      mov [rsp + rdi*2], dx ; store index word
      inc r15
      jmp .scatter_loop
  .scatter_done:
      ; copy scratch back to sort_output
      lea rdi, [rel sort_output]
      xor r15, r15
  .copy_loop:
      cmp r15, r13
      jge .copy_done
      movzx rax, word [rsp + r15*2]
      mov [rdi + r15*2], ax
      inc r15
      jmp .copy_loop
  .copy_done:

      add rsp, 29712
      add rsp, 256*8

      inc r14
      jmp .pass_loop

  .pass_done:
      ; reverse sort_output in-place (ascending -> descending)
      xor r14, r14
      mov r15, r13
      dec r15
  .reverse_loop:
      cmp r14, r15
      jge .reverse_done
      movzx rax, word [r9 + r14*2]
      movzx rbx, word [r9 + r15*2]
      mov [r9 + r14*2], bx
      mov [r9 + r15*2], ax
      inc r14
      dec r15
      jmp .reverse_loop
  .reverse_done:
      LD_REGS
      ret

section .bss
  ; bss data - 256 bytes for user input
  input_buffer resb 256
  input_buffer_len equ $ - input_buffer
  win64_input_num_bytes_read_output resq 1 ; windows ReadFile output

  number_buffer resb 256 ; store formatted string (for u64) for write_fnumber
  double_buffer resb 256 ; store formatted string (for double) for write_fdouble

  ; use temp storage locally in subroutines where you want to pass data through STR_REGS or LD_REGS
  temp_qword resq 1 
  temp_qword_2 resq 1

  sort_output resw 14855
section .data
  yikes_msg db "yikes", 0xA
  yikes_len equ $ - yikes_msg

  newline_msg db 0xA
  newline_len equ $ - newline_msg