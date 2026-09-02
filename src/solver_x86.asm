;---------------------
;  NASM Assembler file
;---------------------
default rel

section .text
  global _start ; linux api
  global main ; windows api

; helper.asm
  extern safe_print_bitmap
  extern print_bitmap
  extern safe_print_word
  extern print_word
  extern print
  extern print_newline
  extern input
  extern yikes
  extern exit
  extern write_fnumber
  extern write_fdouble
  extern sort_array
  extern setup_configuration
  extern test_configuration
  extern measure_start
  extern measure_end

  ; bss
  extern input_buffer ; bss data label - probably just a memory address, like all the other extern labels. all hail the linker
  extern sort_output
  extern configuration

; dict.asm
  extern words

; MARK: Macros
; defines string literal (in .text segment), adds a null terminator, loads its address into rdi
%macro MEASURE_MSG 1
  jmp %%after_msg ; %% is a macro-local label. it's like a . but can be used mutliple times in the same parent label.
  %%msg_str db %1, 0
  %%after_msg:
  lea rdi, [rel %%msg_str]
%endmacro

%macro MSTART 1
  push rsi
  mov rsi, %1
  call measure_start
  pop rsi
%endmacro
%macro MEND 2
  push rsi
  push rdi
  mov rsi, %1
  MEASURE_MSG %2
  call measure_end
  pop rdi
  pop rsi
%endmacro

%include "src\solver_x86.benchmark.s"

; MARK: Main
main:
_start:
  ; Set up arguments for print function
  mov rdi, msg_size
  lea rsi, [rel msg] ; lea rsi, [rel msg] is same as mov rsi, msg. but encoded differently, 
  ; since you put in the DIFFERENCE (maybe only one byte) instead of the MEMORY (8 bytes) as the operand and use a different opcode (lea vs mov).
  ; the instruction still returns the same memory address, it just calculates it at runtime.
  ; must use [rel msg] not [abs msg] or else compiler instantly complains and doesn't compile
  ; solver_x86.obj:solver_x86.asm:(.text+0x1e): relocation truncated to fit: IMAGE_REL_AMD64_ADDR32 against `.data'
  call print

  lea rsi, [rel config_str]
  mov rdi, config_str_len
  call print

  and rsp, 0b1111111111111111111111111111111111111111111111111111111111110000 ; ensure 16 byte aligned

  ; set up config to [arqw_buffer]
  call setup_configuration
  cmp rdi, 2
  jae .ok
    call yikes ; config too short
  .ok:
  call test_configuration

  call benchmark

  MSTART 0
  MEND 0, "Test measurement (empty)"
  
  MSTART 0
  ; MARK: Encode words
  ; words_encoded shall be an array with each element = 8 bytes, storing one word
  ; ex: 00 00 00 00 00 07 04 03, 00 00 00 00 00 0B 08 08, ...
  xor r12d,r12d
  for_word:
    lea rax, [rel words] ; relative adressing REQUIRED?? (cant compile without it)
    lea rax, [rax + r12]
    mov rax, [rax + r12 * 4] ; 8 bytes. contains 1 word and the first 3 letters from the next word

    ; fix little-endian dogshit
    ; we store the data in big-endian because we use db, but when you do mov rax, [mem] it reads a little-endian qword into rax, so we have to swap it.
    bswap rax 
    
    ; ex. aahed aal = 61 61 68 65 64  61 61 6c
    ; subtract 61 to make it 00 00 07 04 03  00 00 0B
    ; shift right 3 bytes to make it 00 00 00 00 00 07 04 03
    mov rbx, 0x6161616161616161
    sub rax, rbx
    shr rax, 24
    ; write the index into the encoded word's first 3 bytes. 00 00 1F = index 31 (see the comment chain around eliminate_based_on_info)
    mov r14, r12
    shl r14, 40
    or rax, r14

    lea rbx, [rel words_encoded]
    mov [rbx+r12*8], rax
    lea rbx, [rel possible_secrets]
    mov [rbx+r12*8], rax
    inc r12
    cmp r12, 14855

    jne for_word
  
  MEND 0, "Encode words"
  MSTART 0

  ; encode bitmap cache
  xor r12d,r12d
  cache_loop:
    lea rbx, [rel words_encoded]
    mov rsi, [rbx + r12*8] ; ps

    pxor xmm0,xmm0
    pxor xmm1,xmm1
    pxor xmm2,xmm2
    
    ; init ltr_count array [u8; 26]
    sub rsp, 32
    movdqu [rsp], xmm0
    movdqu [rsp+16], xmm0
    
    mov r8, 5; iterate from letter 4 to 0 !
    encode_pos_loop:
      dec r8
      ; sil = letter
      movzx rax, sil
      inc byte [rsp+rax] ; add to ltr_count

      imul rbx, r8, 26 ; rbx = r8 * 26; !
      add rbx, rax
      call write_raw_bit

      shr rsi, 8 ; drop last letter
      test r8, r8
      jne encode_pos_loop
    
    xor r8d,r8d
    encode_count_loop:
      ; letter = r8
      ; count = [rsp+r8]
      movzx rax, byte [rsp+r8] ; rax = count

      imul rbx, rax, 26 ; rbx = rax * 26;
      add rbx, 130
      add rbx, r8 
      call write_raw_bit

      inc r8
      cmp r8, 26
      jne encode_count_loop

    add rsp, 32
    ; "lea rax, [rbx + rcx*4 + 16]" MEANS rax = rbx + rcx*4 + 16
    lea rax, [r12*2+r12]
    shl rax, 4
    ; rax is now r12*48

    ; write bitmaps to memory
    lea rbx, [rel cached_bitmaps]
    movdqu [rbx+rax+0], xmm0
    movdqu [rbx+rax+16], xmm1
    movdqu [rbx+rax+32], xmm2
    
    inc r12
    cmp r12, 14855
    jne cache_loop
  
  mov rsi, 0
  MEND 0, "Bitmap cache"

  mov qword [rel len_possible_secrets], 14855

  cmp qword [configuration], 0
  jne solver
  main_loop:
  ; MARK: Input processing
  mov rsi, prompt
  mov rdi, prompt_len
  call print
  call input
  
  ; format: lares __g_y
  ; ensure length >= 11
  cmp rax, 11
  jae no_problem
    call yikes
    jmp main_loop
  no_problem:

  ; bytes 6-10 of input - extract to encoded colors
  lea r8, [rel input_buffer]
  mov r8, [r8 + 6]
  bswap r8
  shr r8, 24
  mov rax, r8
  xor r8d,r8d ; build standard encoded colors
  ; rax is in the form 00 00 00 _ _ g _ y
  
  ; convert (colors as letters) to (standard color form) from right to left
  mov r12, 5

  convert_color_loop: ; r12 from 4..0
    dec r12

    ; jump to correct address based on color (as letter)
    movzx r9, al ; temp r9
    lea rcx, [rel input_jmp_table]
    jmp qword [rcx + r9*8] ; get value at address of jump table
    ; switch statement
      in_yellow:
      lea rcx, [-32 + r12*8]
      neg rcx
      mov edx, 0x01
      jmp write_enc_color
      in_green:
      lea rcx, [-32 + r12*8]
      neg rcx
      mov edx, 0x02
      jmp write_enc_color
      in_gray: ; do nothing
      xor edx,edx

    write_enc_color:
    shl rdx, cl
    or r8, rdx

    
    shr rax, 8 ; drop last letter

    test r12d,r12d
    jne convert_color_loop

  ; bytes 0-4 of input - extract to encoded word

  mov rdi, [rel input_buffer]
  bswap rdi
  mov rbx, 0x6161616161000000
  sub rdi, rbx
  shr rdi, 24

  call index_rdi

  ; input finished processing
  ; rdi = guess in standard form (WITH index)
  ; r8 = colors in standard form

  ; mov rsi, rdi
  ; call safe_print_word
  ; mov rsi, r8
  ; call safe_print_word

  call make_bitmask
  
  ; MARK: Eliminate PS
  ; we clear the entire array and rebuild it each time we eliminate some ps
  ; then we need to store the length of it

  ; [unnecessary] fill PS temp space with 0s
  ; lea rdi, [rel ps_temp_space]
  ; xor rax, rax
  ; mov rcx, 14855 ; qwords to clear
  ; rep stosq

  mov r9, [rel len_possible_secrets] ; counter (not used as index, since it counts down)
  lea rbx, [rel cached_bitmaps]
  lea rcx, [rel possible_secrets]
  lea rdx, [rel ps_temp_space]
  xor r10d,r10d ; new len_ps

  ; we will write the new array to ps_temp_space then copy it over to possible_secrets
  eliminate_based_on_info:
    mov rsi, [rcx] ; rsi = secret
    mov r11, rsi
    shr r11, 40
    ; r11 = index stored in word
    imul r11, r11, 48 ; r11 *= 48

    ptest xmm0, [rbx+r11] ; get bitmap at address using the word index x 48
    jne .word_eliminated
    ptest xmm1, [rbx+r11+16]
    jne .word_eliminated
    ptest xmm2, [rbx+r11+32]
    jne .word_eliminated

    .word_not_eliminated:
    ; write to new list
    mov [rdx], rsi 
    add rdx, 8
    inc r10

    .word_eliminated:
    
    
    add rcx, 8
    dec r9
    jne eliminate_based_on_info

  ; print "Filtered possible secrets: [] -> [] (-[])\n"
  ; use helper.asm/write_fnumber
  mov rsi, filter_1
  mov rdi, filter_1_len
  call print
  mov rdi, [rel len_possible_secrets]
  call write_fnumber
  call print
  mov rsi, filter_2
  mov rdi, filter_2_len
  call print
  mov rdi, r10
  call write_fnumber
  call print
  mov rsi, filter_3
  mov rdi, filter_3_len
  call print
  mov rdi, [rel len_possible_secrets]
  sub rdi, r10
  call write_fnumber
  call print
  mov rsi, filter_4
  mov rdi, filter_4_len
  call print

  mov [rel len_possible_secrets], r10 ; write new length
  ; copy temp ps into real ps
  lea rsi, [rel ps_temp_space] ; src
  lea rdi, [rel possible_secrets] ; dest
  mov rcx, r10 ; count
  cld ; clear direction flag (forward copy)
  rep movsq

  ; now we have filtered possible_secrets and set its new length!

  solver:
  ; MARK: Solver
  ; for PG
  ; for PS
  xor r12d,r12d
  sub rsp, 32
  mov [rsp], r12 ; [rsp] is counter for for_PG loop
  mov qword [rsp+16], 0 ; [rsp+16] is free

  for_PG:
    lea rax, [rel words_encoded]
    mov r12, [rsp] ; temp r12
    mov rdi, [r12*8 + rax] ; pg (last 5 bytes, ignore first 3)

    xor r12d,r12d ; temp r12
    mov [rsp+8], r12 ;[rsp+8] is free
    
    xor r13,r13 ; r13 is total_elim
    ; TODO: Using memory as a counter that is commonly used is inefficient!
    mov qword [rel for_ps_counter], 0 ; counter (goes from 0 -> 14854)
    for_PS:
      lea rbx, [rel possible_secrets]
      mov rsi, [rel for_ps_counter] ; counter
      mov rsi, [rbx + rsi*8] ; ps

      call get_colors ; r8 - colors in the form 00 00 00 01 02 00 02 01
      
      call make_bitmask
    
      mov r9, [rel len_possible_secrets] ; counter
      lea rbx, [rel cached_bitmaps] ; base
      
      ; combine xmm0 and xmm1 into ymm0
      ; vinserti128 ymm0, ymm0, xmm0, 0 ; xmm0 in low bits (lower address goes to low part of ymm register)
      vinserti128 ymm0, ymm0, xmm1, 1 ; xmm1 in high bits

      ; this section runs 3,278,068,076,375 times. it should be really fast.
      for_another_PS:
        dec r9
        lea r14, [rel possible_secrets]
        mov r14, [r14 + r9*8] ; r14 is another_ps
        shr r14, 40 ; r14 is index of another ps
        imul r14, r14, 48 ; r14 *= 48

        ; take bitmaps from memory [ the heap is SLOWWWWWWWW :( ]
        vptest ymm0, [rbx + r14]
        jne .word_eliminated

        ptest xmm2, [rbx + r14 + 32]
        je .word_not_eliminated

        .word_eliminated:
        inc r13 ; add to total_elim
        
        .word_not_eliminated:

        test r9,r9
        jne for_another_PS
      
      inc qword [rel for_ps_counter]
      cmp qword [rel for_ps_counter], 14855
      jne for_PS

    mov r15, [rsp]
    and r15, 0x00_00_00_00_00_00_00_0F
    cmp r15b, 0xF
    jne .dont_print ; only print every 16 words

    ; write " words on average", 0xA
    mov r15, rsp ; copy old rsp
    mov rcx, 18
    .log_3_loop:
      dec rcx
      lea rbx, [rel log_str_3]
      mov al, byte [rbx+rcx]
      dec rsp
      mov [rsp], al
      test rcx,rcx
      jne .log_3_loop
    
    mov [temp_qword_1], rdi
    ; write # eliminated words
    mov rsi, r13
    mov rdi, 14855
    call write_fdouble

    ; copy to stack
    ; rsi = src, rdi = dest, rcx = count
    sub rsp, rdi
    mov rcx, rdi ; count
    mov rdi, rsp ; dest
    cld
    rep movsb
    mov rdi, [temp_qword_1]

    ; write " eliminates "
    mov rcx, 12
    .log_2_loop:
      dec rcx
      lea rbx, [rel log_str_2]
      mov al, byte [rbx+rcx]
      dec rsp
      mov [rsp], al
      test rcx,rcx
      jne .log_2_loop

    ; write GUESS (rdi - guess in the form 00 00 00 00 00 07 04 03)
    mov rcx, 5
    .log_guess_loop:
      dec rcx
      add dil, 0x41
      dec rsp
      mov [rsp], dil ; push letter + 0x41 (letter 'A')
      shr rdi, 8 ; drop last letter    

      test rcx,rcx
      jne .log_guess_loop
    
    ; write "Guess "
    mov rcx, 6
    .log_1_loop:
      dec rcx
      lea rbx, [rel log_str_1]
      mov al, byte [rbx+rcx]
      dec rsp
      mov [rsp], al

      test rcx,rcx
      jne .log_1_loop

    mov r14, r15
    sub r14, rsp ; calculate length of string using difference in stack pointer

    mov rdi, r14 ; length of string
    mov rsi, rsp ; address of string to print is at rsp (not aligned)

    and rsp, 0b1111111111111111111111111111111111111111111111111111111111110000 ; round down to 16 atomically (prevent interrupts using invalid stack with shr 4, shl 4)
    
    call print

    mov rsp, r15 ; revive old rsp

    .dont_print:

    ; add to guess_scores
    mov r15, [rsp] ; counter
    lea r15, [r15 * 8]
    lea r14, [rel guess_scores]
    add r15, r14
    mov [r15], r13 ; r13 is total_elim

    inc qword [rsp]
    cmp qword [rsp], 14855
    jne for_PG
  
  ; end of for_PG
  ; we have guess_scores and words_encoded.
  ; now we need sort the scores, by making a new array of indexes ordered by highest score first
  lea rsi, [rel guess_scores]
  mov rdi, 14855
  call sort_array

  mov r9, 0
  print_top:
  lea r10, [rel sort_output]
  lea r10, [r10 + r9 * 2] ; word (2 bytes)
  movzx r10, word [r10] ; r10 = index of guess
  
  lea r11, [rel guess_scores]
  lea r11, [r11 + r10*8]
  mov r11, [r11] ; r11 = total_elim

  lea r12, [rel words_encoded]
  lea r12, [r12 + r10*8]
  mov r12, [r12] ; r12 = pg

  inc r9

  mov rsi, scoring_1
  mov rdi, scoring_1_len
  call print

  mov rdi, r9
  call write_fnumber
  call print

  mov rsi, scoring_2
  mov rdi, scoring_2_len
  call print

  mov rsi, r12
  call safe_print_word

  mov rsi, scoring_3
  mov rdi, scoring_3_len
  call print

  mov rsi, r11
  mov rdi, 14855
  call write_fdouble
  call print

  mov rsi, scoring_4
  mov rdi, scoring_4_len
  call print


  cmp r9,[configuration + 8] ; print_top_x
  jne print_top
  
  

  mov rsi, press_enter
  mov rdi, press_enter_len
  call print
  call input
  jmp main_loop

  ; exit
  add rsp, 32
  ; Set up arguments for exit function
  xor rdi, rdi
  call exit

; MARK: make_bitmask

; rdi - guess in the form 00 00 00 00 00 07 04 03
; r8 - colors in the form 00 00 00 02 00 00 00 00
; Return: xmm0-2 - bitmask
; modifies: rax, rbx, rcx, rdx, r8, r9, r10, r11, r12, r14, xmm0-3
; preserves: rdi
make_bitmask:
  ; encode 'positions' section of bitmask
  mov r9, 5
  mov rax, rdi ; copy pg into rax


  xor edx,edx ; initialize ltrs_with_maximum (26 bits) (right-to-left)      
  ; initialize minimum_of_ltr array (26 bytes)
  sub rsp, 32
  xor ebx,ebx
  mov [rsp], rbx
  mov [rsp+8], rbx
  mov [rsp+16], rbx
  mov [rsp+24], rbx

  pxor xmm0, xmm0
  pxor xmm1, xmm1
  pxor xmm2, xmm2 ; initialize bitmask

  for_ltr_in_pg: ; iterate right to left (r9 from 4 -> 0)
    dec r9
    ; r8b = colors[r9]
    ; al = pg[r9]

    movzx rbx, r8b; rbx = color (zero-extended). (0,1,2)
    lea r10, [rel jmp_table] ; temp
    jmp qword [r10 + rbx*8]

    gray:
      mov ebx,0b01
      movzx rcx,al
      shl ebx,cl ; shift left by ltr
      or edx,ebx ; write ltrs_with_maximum at al (letter)

      ; set up raw index from row (r9) and letter (al)
      imul rbx, r9, 26 ; rbx = r9d * 26;
      add rbx, rcx

      call write_raw_bit ; input: rbx - index. modifies rcx and rbx
      jmp for_ltr_in_pg_end
    yellow:
      movzx rbx, al
      inc byte [rsp+rbx] ; increase minimum_of_ltr

      imul rcx, r9, 26
      add rbx, rcx

      call write_raw_bit

      jmp for_ltr_in_pg_end
    green:
      movzx rbx, al
      imul rcx, r9, 26
      add rbx, rcx

      call write_raw_bit ; increase minimum_of_ltr

      movzx rbx, al
      inc byte [rsp+rbx]

      imul rbx, r9, 26 ; left
      imul rcx, r9, 26 ; right
      add rcx, 25

      call write_raw_bit_sequence_revised ; rbx - left, rcx - right.

    for_ltr_in_pg_end:

    shr r8, 8 ; drop last color
    shr rax, 8 ; drop last letter

    test r9, r9
    jne for_ltr_in_pg
  
  ; encode 'counts' section
  mov rax, rdi ; copy pg into rax
  mov r9, 5
  mov r10d, edx; copy ltrs_with_maximum array (26 bits) (right-to-left)
  for_ltr_in_pg_2: ; r9 from (4...0)
    dec r9
    ; al = pg[r9] letter
    movzx rcx, al
    ; letter has maximum = leftmost bit of r10d == 1.
    ; cmp r10d, 0b100... or simply cmp r10d, 0.
    mov edx, r10d
    shr edx, cl
    shl edx, 31

    mov r11, 6
    for_count: ; r11 = count (5...0)
      movzx rcx, al ; fix rcx, make it ltr again
      dec r11
      test edx,edx
      je no_max
      
      has_max:
      mov bl, byte [rsp+rcx] ; bl = min
      cmp r11b, bl
      jne write_bit ; only write if count != min
      je continue
      
      no_max:
      mov bl, byte [rsp+rcx] ; bl = min
      cmp r11b, bl
      jae continue ; only write if count < min
      
      write_bit:
        imul rbx, r11, 26
        add rbx, 130 ; count section offset
        add rbx, rcx ; rcx = al = ltr
        call write_raw_bit
      
      continue:
      test r11, r11
      jne for_count

    shr rax, 8
    
    test r9,r9
    jne for_ltr_in_pg_2
  
  add rsp, 32


  ; cmp edi, 0x110607 ; aargh
  ; jne no_debug
  ; mov r9, rsi
  ; mov rax, 0x0000FFFFFFFFFF
  ; and r9, rax
  ; mov rax, 0x000000000F0012 ; aapas
  ; cmp r9, rax
  ; jne no_debug
  ; xchg rdi,rsi
  ; call safe_print_word ; print rdi - guess
  ; xchg rdi,rsi
  ; call safe_print_word ; print rsi - secret
  ; call safe_print_bitmap

  ; hlt
  ; no_debug:

  ; bitmask finished!
  ret

; MARK: Helpers
; rdi - guess in the form 00 00 00 00 00 07 04 03
; rsi - secret in the form 00 00 00 00 02 18 0B 12
; Return: r8 - colors in the form 00 00 00 02 00 00 00 00
; modifies: rax, rbx, rcx, rdx, r8, r9, r11
get_colors:
  ; how_many_yellows: 26-length array of bytes
  sub rsp, 32
  xor eax, eax ; eax automatically zeroes the first 32 bits. not al though. eax is special.
  mov [rsp], rax
  mov [rsp+8], rax
  mov [rsp+16], rax
  mov [rsp+24], rax
  
  xor r8d,r8d; initialize colors array
  
  mov r9,5
  mov rax, rsi ; copy secret into rax
  mov rbx, rdi ; copy guess into rbx
  .add_greens:
    movzx r11d, al ; allow addressing of memory
    inc byte [rsp+r11] ; take the last character of the secret (al)
    cmp al, bl
    
    jne .skip_green ; if secret[i] == guess[i] 

    dec byte [rsp+r11]
    mov r11, 0x0000020000000000
    add r8, r11 ; green on left letter (gets shifted to right at the end)
    
    .skip_green: ; endif  
    
    shr r8, 8 ; shift the colors each time so its correct at the end
    shr rax, 8 ; drop the last character of the secret
    shr rbx, 8 ; drop the last character of the guess
    
    dec r9
    jne .add_greens
  
  ; r8 (colors) is now of the form 00 00 00 02 00 00 02 00
  ; if we set rdx = shl 24, it becomes 02 00 00 02 00 00 00 00
  ; then we can cmp to 01 00 00 00 00 00 00 00 and shl 8 each time to check the letter is gray
  
  ; add yellows from left to right
  xor r9,r9
  mov rbx, rdi ; copy guess into rbx
  bswap rbx ; flip letter order from 00 00 00 00 00 07 04 03 to 03 04 07 00 00 00 00 00
  shr rbx, 24 ; 00 00 00 03 04 07 00 00 (___dehaa)
  mov rdx, r8 ; copy colors into rdx
  shl rdx, 24 ; its now a color checker

  .loop_2:
    mov rax, 0x0100000000000000
    cmp rdx, rax ; if guess[i from 0 -> 4] is yellow or green, skip
    ; bl goes from a->a->h->e->d
    ; rdx's top byte goes from left color to right color (gg___)
    jae .skip
    movzx r11d, bl ; allow addressing of memory
    cmp byte [rsp+r11], 0 ; if how_many_yellows == 0, skip
    je .skip

    dec byte [rsp+r11]
    ; since its gray we can OR it with a 00000001 to change it to yellow
    shr rax, 24 ; offset so we modify the first 4th byte (holds the first color)
    mov rcx, r9 ; r9 goes from 0 -> 4
    shl rcx, 3 ; rcx goes from 0,8,16,24,32
    shr rax, cl ; shift right by 0,8,16,24,32
    or r8, rax
    
    .skip:
    shr rbx, 8 ; drop the last character of the guess
    shl rdx, 8 ; move the color checker to the left
    
    inc r9
    cmp r9, 5
    jne .loop_2

  
  add rsp, 32
  ret

; write a bit into the xmm0-xmm2 bitmap
; rbx: index of bit (0-285)
; modifies: rbx, rcx, xmm0, xmm1, xmm2, xmm3
; output: one of xmm0, xmm1, xmm2 will be updated (via OR with a mask)
write_raw_bit:
  mov rcx, rbx ; somehow i inputted rbx to this function everytime, so im making that the official input

  mov rbx, 1
  shl rbx, 63 ; set up rbx for shifting single bit
  pxor xmm3,xmm3 ; set up xmm3, complementary bitmap for operating
  
  cmp rcx, 127
  jbe .x0
  cmp rcx, 255
  jbe .x1
  ja .x2_left
  .x0:
  cmp rcx, 63
  ja .x0_right
  .x0_left:
  shr rbx, cl ; position rbx 
  ; pinsrq xmm_dest, r64_or_mem, imm8: 
  ; Take a 64-bit value from a general-purpose register (or memory), put it into either the low 
  ; or high 64 bits of an XMM register, and leave the other 64 bits alone.
  pinsrq xmm3, rbx, 1
  por xmm0, xmm3
  ret
  .x0_right:
  sub rcx, 64
  shr rbx, cl
  pinsrq xmm3, rbx, 0
  por xmm0, xmm3
  ret

  .x1:
  cmp rcx, 191
  ja .x1_right
  .x1_left:
  sub rcx, 128
  shr rbx, cl
  pinsrq xmm3, rbx, 1
  por xmm1, xmm3
  ret
  .x1_right:
  sub rcx, 192
  shr rbx, cl
  pinsrq xmm3, rbx, 0
  por xmm1, xmm3
  ret
  
  .x2_left:
  sub rcx, 256
  shr rbx, cl
  pinsrq xmm3, rbx, 1
  por xmm2, xmm3
  ret
  
  .finish:
  


; [DEPRECATED] uses too many registers and likely doesn't function. use write_raw_bit_sequence_revised.
; write a sequence of bits into the xmm0-xmm2 bitmap
; rbx: index of leftmost bit (0-285)
; rcx: index of rightmost bit (0-285)
; modifies: rbx, rcx, r10, r11, r12, r14, r15, xmm0, xmm1, xmm2, xmm3
; output: xmm0, xmm1, xmm2 will be updated (via XOR with a mask)
write_raw_bit_sequence:
  push r11
  push r14 ; bad but sadly need it (for the .loop section)
  mov r11, rbx
  mov r14, rcx

  ; r11 = left, r14 = right
  shr rbx, 6
  shr rcx, 6
  cmp rbx, rcx
  je .do_it

  ; recursion time

  ; we know we start at the leftmost.
  jmp .leftmost 
  .leftmost:
      ; leave rbx alone (starting index)
      mov rbx, r11
      mov rcx, r11
      shr rcx, 6
      shl rcx, 6
      ; and rcx, 0b00000000
      add rcx, 63 ; rcx = round_down(64) + 63

      call write_raw_bit_sequence
  
  ; we also know we have a rightmost. (at least 2)
  jmp .rightmost
  .rightmost:
      mov rbx, r11
      shr rbx, 6
      shl rbx, 6  ; rbx = seg * 64
      ; leave rcx alone (ending index)
      mov rcx, r14
      call write_raw_bit_sequence
  
  ; r11 is the left value. we will iterate and keep adding 64 to it.
  add r11, 64 ; start 1 segment from the leftmost
  sub r14, 64 ; end 1 segment from the rightmost
  .loop:
    ; floor the current segment
    mov rbx, r11
    shr rbx, 6
    shl rbx, 6 ; start of seg

    mov rcx, r11
    shr rcx, 6
    shl rcx, 6
    add rcx, 63 ; end of seg

    call write_raw_bit_sequence ; fill entire segment

    add r11, 64
    cmp r11, r14
    jbe .loop

  pop r14
  pop r11
  ret

  .do_it:
    mov rcx, r14 ; move r14 (right) into rcx

    mov r12, r11 ; move r11 (left) into r12
    shr r12, 6 ; turn r12 into segment (0-5)
    shl r12, 6 ; get base index
    sub rbx, r12
    sub rcx, r12 ; localize rbx and rcx indexes to the segment
    shr r12, 6 ; revert change to r12 (make it segmnent again)

    ; rcx is now a temp var used for shifting math (original MOVED to r15)
    mov r15, rcx
    mov r10, 1 ; init r10: bitmap to write into xmm3
    pxor xmm3, xmm3 ; init xmm3: actual bitmap for XORing
    sub rcx, rbx
    add rcx, 1
    ; why did shl r10 (00000001), 64 not work???? r10 shouldve become 0, but it stayed as 1! ... shifts by >=64 wrap around to 0... ughh... lets put some workaround logic in here
    cmp cl, 64
    jb .below_64
    xor r10d,r10d ; workaround to make it 0 if shifting by >=64
    .below_64:
    shl r10, cl
    sub r10, 1 ; (1u64 << (right-left+1)) - 1)
    mov rcx, 63
    sub rcx, r15
    shl r10, cl
    ; r12 is the segment we want to write to (0-4)
    cmp r12, 3
    ja .x2_left
    je .x1_right
    cmp r12, 1
    ja .x1_left
    je .x0_right
    jb .x0_left

    .x0_left:
      pinsrq xmm3, r10, 1
      pxor xmm0, xmm3
      jmp .end_it
    .x0_right:
      pinsrq xmm3, r10, 0
      pxor xmm0, xmm3
      jmp .end_it
    .x1_left:
      pinsrq xmm3, r10, 1
      pxor xmm1, xmm3
      jmp .end_it
    .x1_right:
      pinsrq xmm3, r10, 0
      pxor xmm1, xmm3
      jmp .end_it
    .x2_left:
      pinsrq xmm3, r10, 1
      pxor xmm2, xmm3
    .end_it:
      pop r14
      pop r11
      ret

; write a sequence of bits into the xmm0-xmm2 bitmap
; rbx: index of leftmost bit (0-285)
; rcx: index of rightmost bit (0-285)
; modifies: rbx, rcx, r10, r11, r12, r14, xmm0, xmm1, xmm2, xmm3
; output: xmm0, xmm1, xmm2 will be updated (via xor with a mask)
write_raw_bit_sequence_revised:
  ; break it into a list of (left and right from 0-64, segment) union (full segments)
  mov r10, rbx ; make r10 the counter

  ; loop section: calculates how many in-between segments are entirely filled, and entirely fill them.
  ; ex: (left 74) (right 250) -> technically only one segment can be entirely filled (indices 128-191)
  ; to find that, we take left and round it up to nearest 64. then, we take right and round down to nearest 64.
  ; then, everything within that area can be entirely filled.
  ; implementation: r10 starts at (left rounded up 64) and keep adding 64 until it is higher than (right)
  ; in the example it will iterate with r10 = 128, then r10 = 192.
  ; we should ignore the first iteration, so just r10 = 192, and fill from 128-191 there.
  and r10, 0b1111111111111111111111111111111111111111111111111111111111000000
  add r10, 64 ; round up to nearest (higher) 64

  .loop_first_iter:
  add r10, 64
  cmp r10, rcx
  jg .break 
  ; ex. 0-100
  ; -> 64-100
  ; -> 128 vs 100
  ; break

  .loop_real:
  ; fill from (r10-64 to r10-1 inclusive) (ex. 64 - 127)
  mov r14, 0b1111111111111111111111111111111111111111111111111111111111111111
  mov r12, r10
  shr r12, 6
  sub r12, 1
  call bigpinsrq

  add r10, 64
  cmp r10, rcx
  jle .loop_real

  .break:

  ; now time to fill the leftmost and rightmost segment

  mov r11, rbx
  shr r11, 6 ; r11 = left seg
  mov r12, rcx
  shr r12, 6 ; r12 = right seg

  and rbx, 0b0000000000000000000000000000000000000000000000000000000000111111; rbx is now local (0-63) to the left segment
  and rcx, 0b0000000000000000000000000000000000000000000000000000000000111111 ; rcx is now also local (0-63) to the right segment.
  cmp r11, r12
  jne .isnt
  ; if the left and right segment are the same, fill from (local rbx - local rcx) on that segment
  mov r14, 0b1111111111111111111111111111111111111111111111111111111111111111
  ; to fill from (50 - 51)
  ; first << by 62 (63 - (right-left))
  ; then >> by 50 (left)
  sub rcx, rbx
  neg rcx
  add rcx, 63
  shl r14, cl
  mov rcx, rbx
  shr r14, cl
  call bigpinsrq
  ret

  .isnt:
  ; if the left and right segment are different

  ; fill from (0 - local rcx) on the right seg
  mov r14, 0b1111111111111111111111111111111111111111111111111111111111111111
  neg rcx
  add rcx, 63 ; make cl = 63 - rcx
  shl r14, cl
  call bigpinsrq
  
  ; fill from (local rbx - 63) on the left seg
  mov r14, 0b1111111111111111111111111111111111111111111111111111111111111111
  mov rcx, rbx ; now we can override rcx without worry, we won't need it anymore
  shr r14, cl ; shr by rbx
  mov r12, r11 ; move (left seg index) into subroutine input
  call bigpinsrq

  ret

  
; r12 - index to insert to (0-4)
; r14 - bitmap to insert, which will be XORed with the correct xmm register
; modifies: only xmm0-3
bigpinsrq:
  pxor xmm3,xmm3
  cmp r12, 3
  ja .x2_left
  je .x1_right
  cmp r12, 1
  ja .x1_left
  je .x0_right
  jb .x0_left

  .x0_left:
    pinsrq xmm3, r14, 1
    pxor xmm0, xmm3
    jmp .end_it
  .x0_right:
    pinsrq xmm3, r14, 0
    pxor xmm0, xmm3
    jmp .end_it
  .x1_left:
    pinsrq xmm3, r14, 1
    pxor xmm1, xmm3
    jmp .end_it
  .x1_right:
    pinsrq xmm3, r14, 0
    pxor xmm1, xmm3
    jmp .end_it
  .x2_left:
    pinsrq xmm3, r14, 1
    pxor xmm2, xmm3
  .end_it:
    ret

; rdi - word (without 3-byte index)
; slow; iterates through dictionary to match word
; modifies: r13, rsi, rdi, rbx
; Return: gives rdi an index (00 00 1F = index 31)
index_rdi:
  xor r13d, r13d
  .loop:

  lea rbx, [rel words_encoded]
  mov rsi, [rbx + r13*8] ; encoded word
  cmp rdi, rsi
  je .done

  mov rbx, 0x00_00_01_00_00_00_00_00
  add rdi, rbx

  inc r13
  cmp r13, 14855
  jne .loop

  .done:
  ret


; MARK: Data
jmp_table:
  dq gray
  dq yellow
  dq green

input_jmp_table:
  ; (every letter is gray except 'g', 'y')

  times 0x67 dq in_gray ; define 0x67 quadwords of in_gray
  dq in_green
  times (0x79 - 0x67 - 1) dq in_gray ; define 17 qwords of in_gray
  dq in_yellow
  times 200 dq in_gray ; define a bunch more of in_gray

section .data
  msg db "Hello, world!", 0xA
  msg_size equ $ - msg
  log_str_1 db "Guess "
  log_str_2 db " eliminates "
  log_str_3 db " words on average", 0xA
  ; literal 36 + 1 ending byte + 5 letters from guess = 42

  prompt db "Enter guess and result (lares __g_y): "
  prompt_len equ $ - prompt
  
  press_enter db "Press enter to continue...", 0xA
  press_enter_len equ $ - press_enter

  filter_1 db "Filtered possible secrets: " 
  filter_1_len equ $ - filter_1
  filter_2 db " -> "
  filter_2_len equ $ - filter_2
  filter_3 db " (-"
  filter_3_len equ $ - filter_3
  filter_4 db ")", 0xA
  filter_4_len equ $ - filter_4
  ; by the way, we do printing formatted strings 2 ways.
  ; - pushing the entire composite string onto the stack and printing with that set as address (like we do for log_str1-3) (this method is worse since i have to change code every time i change length of string)
  ; - printing in segments, like printing "Eliminated ", then printing a number from the stack, then printing "words", 0xA
  ; (i could make a printf subroutine later if i feel like it)

  scoring_1 db "#"
  scoring_1_len equ $ - scoring_1 
  scoring_2 db " Guess "
  scoring_2_len equ $ - scoring_2
  scoring_3 db " eliminates "
  scoring_3_len equ $ - scoring_3
  scoring_4 db " words on average", 0xA
  scoring_4_len equ $ - scoring_4

  config_str db "Configuration: ", 0xA
  config_str_len equ $ - config_str
section .bss
  ; each word is 8 bytes (left 3 are index, right 5 are u8 letters)
  ; 14855 words * 8 = 118840 bytes
  words_encoded resb 118840 ; dictionary
  guess_scores resq 14855

  alignb 16
  possible_secrets resb 118840 ; dictionary, but is changed as we eliminate words
  len_possible_secrets resq 1
  for_ps_counter resq 1 ; i want this near possible_secrets and cached_bitmaps so we get more cache hits

  ; each bitmap needs to store 26*11 bits via 3 XMM registers. (16*3 = 48 bytes)
  ; there are 14855 bitmaps. 14855*48 = 713040
  alignb 16 ; yay! this works. now ptest doesnt give an exception.
  cached_bitmaps: resb 713040

  alignb 16
  ps_temp_space resb 118840 ; temp space

  temp_qword_1 resq 1
