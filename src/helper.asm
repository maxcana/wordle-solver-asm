; printing, input handling, parsing, debugging utility
; + wrappers for linux and windows ABIs
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
    global setup_configuration
    global test_configuration
    global measure_start
    global measure_end
    global cstr_len

  ; bss
    global input_buffer ; bss data - output of input subroutine
    global sort_output
    global configuration
    

; windows api stuff
%ifdef WINDOWS
  extern GetStdHandle
  extern WriteFile
  extern ExitProcess
  extern ReadFile
  extern CreateFileA
  extern CloseHandle
  extern GetLastError
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

; MARK: Random utility

; call when something goes wrong
; preserves: everything
yikes:
  push rsi
  push rdi
  mov rsi, yikes_msg
  mov rdi, yikes_len
  call print
  %ifdef WINDOWS
  call GetLastError
  mov rdi, rax
  call write_fnumber
  call print ; error num
  %endif
  pop rdi
  pop rsi
  ret

; store the current cycle count in the measurement table for a measurement id
; sil - measurement id (for concurrent measurements)
; preserves: everything
measure_start:
  mov byte [temp_qword], sil
  STR_REGS
  movzx rsi, byte [temp_qword]

  rdtscp
  shl rdx, 32
  or rax, rdx ; rax = cycle count

  lea rdx, [rel measurement_table]
  mov [rdx + rsi], rax ; store cycle count in measurement_table
  LD_REGS
  ret

; print the cycles elapsed from entry sil in the measurement table
; sil - measurement id
; rdi - ptr to cstr holding measurement name to print
; preserves: everything
measure_end:
  mov byte [temp_qword], sil
  mov [temp_qword_2], rdi
  STR_REGS
  movzx rsi, byte [temp_qword]
  mov r15, [temp_qword_2]

  rdtscp
  shl rdx, 32
  or rax, rdx ; rax = cycle count

  lea rdx, [rel measurement_table]
  mov rbx, [rdx + rsi] ; rbx = old cycle count

  sub rax, rbx
  ; rax = cycles elapsed
  
  mov rsi, measure_1
  mov rdi, measure_1_len
  call print

  mov rsi, r15
  call cstr_len
  call print

  mov rsi, measure_2
  mov rdi, measure_2_len
  call print

  mov rsi, rax
  mov rdi, 1000000
  call write_fdouble
  call print

  mov rsi, measure_3
  mov rdi, measure_3_len
  call print

  LD_REGS
  
  ret 

; MARK: String utils

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

; writes the result of the division with 3 digits after decimal of precision (floored)
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
  cvtsi2sd xmm6, r9 ; xmm6 = 1000
  mulsd xmm4, xmm6 ; xmm4 = 454.3
  cvttsd2si rbx, xmm4 ; rbx = 454

  ; now to write the string into the buffer
  mov rdi, rax
  call write_fnumber

  ; copy to buffer (rbp is buffer index)
  ; rsi = src, rdi = dest, rcx = count
  mov rcx, rdi ; count
  lea rdi, [rel double_buffer] ; dest
  cld
  rep movsb
  add rdi, rcx

  ; write the period
  mov byte [rdi], '.'
  inc rdi
  mov rbp, rdi

  mov rdi, rbx
  call write_fnumber

  ; copy to buffer again (rbp is buffer index)
  mov rcx, rdi ; count
  mov rdi, rbp ; dest
  add rbp, rcx
  cld
  rep movsb ; by the way, rep movsb clobbers rsi, rdi, rcx
  

  ; outputs
  mov rdi, rbp
  lea rax, [rel double_buffer]
  sub rdi, rax ; rdi = length

  mov [rel temp_qword], rdi
  LD_REGS
  lea rsi, [rel double_buffer]
  mov rdi, [rel temp_qword]
  ret

; rsi - ptr to first char of cstr
; return: rdi - length of cstr (excluding the "null-terminator" 0)
; preserves: everything
cstr_len:
  xor edi, edi
  .loop:
    cmp byte [rsi + rdi], 0 ; end of cstr
    je .end
  inc rdi
  jmp .loop
  .end:
  ret

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
  mov rdi, 0x4141414141414141
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
  ret

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

; read the config file and put its contents into memory at [config_buffer]
; preserves: everything
; Return: rdi - bytes read (length of contents)
read_config:
  STR_REGS
  PLATFORM_CALL win64_read_config, linux_read_config
  mov [temp_qword], rdi
  LD_REGS
  mov rdi, [temp_qword]
  ret

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

; read the config file and put its contents into memory at [config_buffer]
; modifies: caller-saved registers + more
; Return: rdi - bytes read (length of contents)
linux_read_config:
  ; get the file descriptor
  mov rax, 2 ; sys_open
  lea rdi, [rel config_filename] ; path
  mov rsi, 0 ; O_RDONLY
  mov rdx, 0 ; mode
  syscall

  test rax, rax
  js .error ; negative fd = error
  mov r14, rax ; r14 = file descriptor

  ; read into buffer
  mov rax, 0 ; sys_read
  mov rdi, r14 ; file descriptor
  mov rsi, config_buffer ; address of buffer to store config file
  mov rdx, config_buffer_len
  syscall
  ; rax = bytes read
  mov r15, rax ; move into callee-saved (safe) register

  ; close the file (free the descriptor, that's cool i didnt know thats how it worked!)
  mov rax, 3 ; sys_close
  mov rdi, r14
  syscall

  mov rdi, r15
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

; read the config file and put its contents into memory at [config_buffer]
; modifies: caller-saved registers + more
; Return: rdi - bytes read (length of contents)
win64_read_config:
  sub rsp, 8 ; [ 8 unused, for alignment ]

  ; CreateFileA(LPCSTR lpFileName, dwDesiredAccess, dwShareMode, lpSecurityAttributes, dwCreationDisposition, dwFlagsAndAttributes, hTemplateFile)
  lea rcx, [rel config_filename] ; #1 lpFileName
  mov rdx, 0x80000000 ; #2 GENERIC_READ
  mov r8, 0 ; #3 no sharing
  mov r9, 0 ; #4 NULL
  push 0 ; #7 NULL
  push 0x80 ; #6 FILE_ATTRIBUTE_NORMAL
  push 3 ; #5 OPEN_EXISTING
  sub rsp, 32 ; [32 shadow ... 24 local ( from pushing ) ... 8 unused, for alignment ]
  call CreateFileA
  add rsp, 64 ; reset rsp

  cmp rax, -1 ; INVALID_HANDLE_VALUE
  jne .no_error
    call yikes ; why is this hit?
    ret
  .no_error:

  mov r14, rax ; rax = config handle

  ; ReadFile(handle, buffer, len, &bytes_read, lpOverlapped)
  
  mov rcx, r14
  lea rdx, [rel config_buffer]
  mov r8, config_buffer_len
  lea r9, [rel win64_input_num_bytes_read_output]
  push 0 ; lpOverlapped (NULL)
  sub rsp, 32 ; [... 32 shadow space]
  call ReadFile
  mov qword r15, [rel win64_input_num_bytes_read_output]
  add rsp, 40 ; reset rsp

  ; CloseHandle(handle)
  mov rcx, r14 ; r14 = handle
  sub rsp, 32
  call CloseHandle
  add rsp, 32

  mov rdi, r15 ; r15 = num bytes read
  ret


%endif


; MARK: Sorting

; n^2 sorter (MEGA SLOW, performance doesnt matter here though)
; rsi - pointer to array of qwords
; rdi - length of array (maximum 14855)
; the array must not contain any values equal to i64 min value
; outputs: array of words length rdi located at [sort_output]: indexes corresponding to values on the original array (from signed highest to lowest)
; preserves: everything
sort_array:
  mov [temp_qword], rsi
  mov [temp_qword_2], rdi
  STR_REGS
  mov rsi, [temp_qword] ; start
  
  ; rsi = src, rdi = dest, rcx = count
  lea rdi, [rel sort_buffer] ; dest
  mov rcx, [temp_qword_2] ; length
  cld
  rep movsq

  lea rsi, [rel sort_buffer] ; rsi is the copied array
  mov rdi, [temp_qword_2] ; rdi is the length
  lea rbx, [rel sort_output]

  mov rdx, 0
  .loop:
    call find_highest_value_signed
    ; remove the highest value from array (replace with min value)
    mov rax, 0b1000000000000000000000000000000000000000000000000000000000000000
    mov [rsi + r11*8], rax

    ; add index of highest value to output
    mov word [rbx], r11w
    add rbx, 2
  inc rdx
  cmp rdx, rdi
  jne .loop

  LD_REGS
  ret

; rsi - address of array of qwords
; rdi - length of array
; modifies: r9, r10, r11
; return:
; r10 - highest value
; r11 - index of highest value
find_highest_value_signed:
  ; iterate through array, r9: 0 -> 14854, find the highest value
  ; each time replace the highest value with MIN VALUE
  mov r9, 0
  mov r10, 0b1000000000000000000000000000000000000000000000000000000000000000 ; r10 = highest val
  mov r11, -1 ; index of highest val
  .loop:
  
  cmp r10, [rsi + r9*8]
  jge .nothing
  ; if it is less (value > max), then:
  ; set r10 to the higher value
  ; set r11 to the index
  mov r10, [rsi + r9*8]
  mov r11, r9

  .nothing:
  
  inc r9
  cmp r9, rdi
  jne .loop
ret
; MARK: arqw

; read and parse config.arqw into an array
; preserves: everything except rsi and rdi
; return:
; [configuration] - parsed array of qwords
; rdi - length of array
setup_configuration:
  call read_config
  lea rsi, [rel config_buffer]
  call parse_arqw
  ret

; print the configuration array
; rdi - length of config array
; modifies: rax, rbx, rsi, rdi
test_configuration:
  mov rax, rdi ; index + 1
  lea rbx, [rel configuration]
  .loop:
  mov rdi, [rbx]
  call write_fnumber
  call print
  call print_newline
  
  add rbx, 8
  dec rax
  jne .loop
  ret

; parse arqw file (u64 numbers separated by lines)
; it will parse the first number string in each line, and ignore everything else. skipping lines without numbers.
; rsi - memory address of arqw string
; rdi - length of arqw string
; preserves: everything, except rdi
; return:
; [configuration] - parsed array of qwords
; rdi - length of array
parse_arqw:
  mov [rel temp_qword], rsi
  mov [rel temp_qword_2], rdi
  STR_REGS
  mov rax, [rel temp_qword] ; rax = address of first character
  mov rbx, [rel temp_qword_2]
  add rbx, rax ; rbx = address right after last character

  mov r10, rax ; start of current line
  mov r9, rax ; index

  lea rsi, [rel configuration] ; address of new element in array
  mov rdi, 0 ; length of array
  .for_each_line:
    inc r9
    cmp r9, rbx
    je .r9_at_end
    cmp byte [r9], 0xA
    jne .for_each_line
    ; if [r9] =  0xA, line is from from [r10, r9)
    call deal_with_line
    mov r10, r9
    add r10, 1
    cmp rdx, 0 ; no number in line, go to next line
    je .for_each_line
      ; if there is number in line
      call parse_u64 
      mov [rsi], rcx
      add rsi, 8
      inc rdi
    cmp r9, rbx
    jne .for_each_line

  .r9_at_end:
  ; if r9 = rbx (end), last line is from [r10, r9)
  call deal_with_line
  cmp rdx, 0 ; no number in line, go to end
  je .end
    ; if there is number in line
    call parse_u64 
    mov [rsi], rcx
    add rsi, 8
    inc rdi
  
  .end:

  mov [temp_qword], rdi ; length
  LD_REGS
  mov rdi, [temp_qword]
  ret
  

; r10 - line left (incl.)
; r9 - line right (excl.)
; line structure: "   stuff anything *#&$)@&*%)#  342489  [randomthings that arent numbers] ;  comment here   \r" or " ; 4328 is a cool number"
; modifies: r13, r14, r15
; Return:
; rdx: 0 or 1, is there a number in the line?
; r14 - start address of number (incl.) (0 if no number in line)
; r15 - end address of number (incl.) (0 if no number in line)
deal_with_line:
  ; ignore: ' ', '\r'
  ; return early on ';'
  mov r13, r10
  mov rdx, 0 ; default = fail
  mov r14, 0 ; start of number
  mov r15, 0 ; end of number

  .loop:
    cmp byte [r13], "0"
    jb .not_num
    cmp byte [r13], "9"
    ja .not_num
    ; if no start of number defined, define the start of number
    cmp r14, 0
    jne .start_already_defined
    mov r14, r13 ; start of number
    .start_already_defined:
    jmp .next

      .not_num:
      ; if start of number already defined, and we hit a non-number, define the end of number and exit.
      cmp r14, 0
      je .next
        mov r15, r13
        sub r15, 1
        mov rdx, 1
        jmp .done ; found start and end of number

    .next:
    cmp byte [r13], ";"
    je .done

    inc r13

    cmp r13, r9
    jne .loop
  
  ; if we iterated through the whole line, check if we have a start of number.
  mov rdx, 0
  cmp r14, 0
  je .done ; if no start of number, we dont give an end of number
  ; if there is a start of number, this means the number took the entire line (and no \r at end of line). give the end as the last character
  mov r15, r9 
  sub r15, 1
  mov rdx, 1

  .done:
  
  ret

; r14 - start address of number string (incl.)
; r15 - end address of number string (incl.)
; modifies: r13, rdx, r12, r11, rcx
; Return: rcx - number
parse_u64:
  ; iterate through each byte, subtract "0"
  mov r13, r15 ; r13 = current address (absolute)
  mov r11, 1 ; r11 = digit multiplier, ones digit first
  mov rcx, 0
  .loop:
    movzx rdx, byte [r13]
    sub rdx, "0"
    ; convert to hex by using summing 10*each byte
    
    mov r12, rdx
    imul r12, r11 ; r12 = dl * (digits place)
    imul r11, r11, 10 ; r11 = 10 * r11
    add rcx, r12 ; sum it

    dec r13
    cmp r13, r14
    jae .loop
  
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

  parse_u64_temp_qword resq 1
  configuration resq 100

  sort_buffer resq 14855
  sort_output resw 14855

  config_buffer resb 16384 ; maximum fize size = 16KB
  config_buffer_len equ $ - config_buffer

  measurement_table resq 256
section .data
  yikes_msg db "yikes", 0xA
  yikes_len equ $ - yikes_msg

  newline_msg db 0xA
  newline_len equ $ - newline_msg

  config_filename db "C:\\user\\dev\\assembly\\wordle-solver-asm\\config.arqw", 0

  measure_1 db `Measurement \"`
  measure_1_len equ $ - measure_1
  measure_2 db `\" completed in `
  measure_2_len equ $ - measure_2
  measure_3 db " megacycles", 0xA
  measure_3_len equ $ - measure_3