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
  extern input
  extern win64_exit
  extern linux_exit
  extern input_buffer ; bss data label - probably just a memory address, like all the other extern labels. all hail the linker

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

  ; encode words
  ; words_encoded shall be an array with each element = 8 bytes, storing one word
  ; ex: 00 00 00 00 00 07 04 03, 00 00 00 00 00 0B 08 08, ...
  xor r12d,r12d
  for_word:
    lea rax, [rel words] ; relative adressing REQUIRED?? (cant compile without it)
    lea rax, [rax + r12]
    mov rax, [rax + r12 * 4] ; 8 bytes. contains 1 word and the first 3 letters from the next word
    bswap rax ; fix little-endian dogshit
    ; ex. aahed aal = 61 61 68 65 64  61 61 6c
    ; subtract 61 to make it 00 00 07 04 03  00 00 0B
    ; shift right 3 bytes to make it 00 00 00 00 00 07 04 03
    mov rbx, 0x6161616161616161
    sub rax, rbx
    shr rax, 24
    lea rbx, [rel words_encoded]
    mov [rbx+r12*8], rax
    lea rbx, [rel possible_secrets]
    mov [rbx+r12*8], rax
    inc r12
    cmp r12, 14855

    jne for_word
  
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
  
  ; begin main solver
  ; for PG
  ; for PS
  xor r12d,r12d
  sub rsp, 32
  mov [rsp], r12 ; [rsp] is counter for outermost loop
  mov [rsp+16], r12 ; [rsp+16] is number of possible secrets remaining

  solve:
  mov rsi, prompt
  mov rdi, prompt_len
  call print
  call input
  
  ; format: lares __g_y
  ; ensure length >= 11
  cmp rax, 11
  jae no_problem
    call yikes
    jmp solve
  no_problem:

  ; bytes 6-10 of input - extract to encoded colors
  lea rdx, [rel input_buffer]
  mov rdx, [rdx + 6]
  shr rdx, 24
  mov rax, rdx
  xor edx,edx ; build standard encoded colors
  ; rax is in the form 00 00 00 _ _ g _ y
  
  ; convert (colors as letters) to (standard color form) from right to left
  mov r12, 5
  .convert_color: ; r12 from 4..0
  dec r12

  ; jump to correct address based on letter
  movzx rcx, al
  mov rcx, [input_jmp_table + rcx*8]
  jmp rcx 
  ; switch statement
    in_yellow:
    lea rcx, [-32 + r12*8]
    neg rcx
    movzx r8, 0x01
    jmp .write
    in_green:
    lea rcx, [-32 + r12*8]
    neg rcx
    movzx r8, 0x02
    in_gray: ; do nothing

  .write:
  shl r8, cl
  or rdx, r8

  
  shr al, 8 ; drop last letter

  test r12d,r12d
  jne .convert_color

  ; bytes 0-4 of input - extract to encoded word

  mov rdi, [rel input_buffer]
  bswap rdi
  mov rbx, 0x6161616161616161
  sub rdi, rbx
  shr rdi, 24
  


  ; rdi = guess in standard form
  ; rdx = colors in standard form



  for_PG:
    lea rax, [rel words_encoded]
    mov r12, [rsp] ; temp r12
    mov rdi, [r12*8 + rax] ; pg (last 5 bytes, ignore first 3)

    xor r10d,r10d ; temp r10
    mov [rsp+8], r10; [rsp+8] is total_elim
    xor r13d,r13d
    for_PS:
      lea rbx, [rel words_encoded]
      mov rsi, [rbx + r13*8] ; ps
      call get_colors ; r8 - colors in the form 00 00 00 01 02 00 02 01
  
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
        lea r15, [rel jmp_table] ; temp
        jmp qword [r15 + rbx*8]
  
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
    
        mov r11b, 6
        for_count: ; r11 = count (5...0)
          movzx rcx, al ; fix rcx, make it ltr again
          dec r11b
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
          test r11b, r11b
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
    
      mov r9, 14855 ; counter
      lea rbx, [rel cached_bitmaps] ; memory pointer

      for_another_PS:
        ; take bitmaps from memory [ the heap is SLOWWWWWWWW :( ]
        ptest xmm0, [rbx] ; ptest only works on 16-byte aligned aligned xmmwords
        jne word_eliminated

        ptest xmm1, [rbx+16]
        jne word_eliminated

        ptest xmm2, [rbx+32]
        je word_not_eliminated

        word_eliminated:
        ; WOAH why are we using the stack, lets use a register, YIKES yikes yikes
        inc qword [rsp+8] ; add to total_elim
        
        word_not_eliminated:

        add rbx, 48
        dec r9
        jne for_another_PS
      
      inc r13
      cmp r13, 14855
      jne for_PS
  
    ; write " words on average", 0xA
    mov r15, rsp ; copy old rsp
    mov rcx, 18
    log_3_loop:
      dec rcx
      lea rbx, [rel log_str_3]
      mov al, byte [rbx+rcx]
      dec rsp
      mov [rsp], al
      test rcx,rcx
      jne log_3_loop
    
    
    ; write # eliminated words
    mov rcx, 10 ; divisor for div ecx
    mov rax, [r15+8] ; total_elim, lower 32 bits of dividend
    log_int_loop:
      xor edx,edx ; higher 32 bits of dividend
      ; eax = dividend
      div ecx ; divisor

      ; eax is quotient
      ; edx is remainder
      dec rsp
      add rdx, "0" ; add the ascii value for "0" (0x30)
      mov [rsp], dl
      ; push remainder (last digit) and replace old value with quotient
      cmp eax, 0
      jne log_int_loop

    ; write " eliminates "
    mov rcx, 12
    log_2_loop:
      dec rcx
      lea rbx, [rel log_str_2]
      mov al, byte [rbx+rcx]
      dec rsp
      mov [rsp], al
      test rcx,rcx
      jne log_2_loop

    ; write GUESS (rdi - guess in the form 00 00 00 00 00 07 04 03)
    mov rcx, 5
    log_guess_loop:
      dec rcx
      add dil, 0x41
      dec rsp
      mov [rsp], dil ; push letter + 0x41 (letter 'A')
      shr rdi, 8 ; drop last letter    

      test rcx,rcx
      jne log_guess_loop
    
    ; write "guess "
    mov rcx, 6
    log_1_loop:
      dec rcx
      lea rbx, [rel log_str_1]
      mov al, byte [rbx+rcx]
      dec rsp
      mov [rsp], al

      test rcx,rcx
      jne log_1_loop

    mov r14, r15
    sub r14, rsp ; calculate length of string using difference in stack pointer

    mov rdi, r14 ; length of string
    mov rsi, rsp ; address of string to print is at rsp (not aligned)

    and rsp, 0b1111111111111111111111111111111111111111111111111111111111110000 ; round down to 16 atomically (prevent interrupts using invalid stack with shr 4, shl 4)
    
    call print

    mov rsp, r15 ; revive old rsp

    inc qword [rsp]
    cmp qword [rsp], 14855
    jne for_PG
  
  mov rsi, press_enter
  mov rdi, press_enter_len
  call print
  call input
  jmp solve

  add rsp, 32
  ; Set up arguments for exit function
  xor rdi, rdi
  call win64_exit

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
  

; write a sequence of bits into the xmm0-xmm2 bitmap
; rbx: index of leftmost bit (0-285)
; rcx: index of rightmost bit (0-285)
; modifies: rbx, rcx, r10, r11, r12, r14, r15, xmm0, xmm1, xmm2, xmm3
; output: xmm0, xmm1, xmm2 will be updated (via XOR with a mask)
write_raw_bit_sequence:
  push r11
  push r14 ; yikes yikes yikes but sadly need it (for the .loop section)
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
jmp_table:
  dq gray
  dq yellow
  dq green

input_jmp_table:
  ; (every letter is gray except 'g', 'y')

  times 0x67 dq in_gray ; define 0x67 quadwords of in_gray
  dq in_yellow
  times (0x79 - 0x67 - 1) dq in_gray ; define 17 qwords of in_gray
  dq in_green
  times 200 dq in_gray ; define a bunch more of in_gray

section .data
  msg db "Hello, world!", 0xA
  msg_size equ $ - msg
  words db "aahedaaliiaapasaarghaartiabacaabaciabackabacsabaftabahtabakaabampabandabaseabashabaskabateabayaabbasabbedabbesabbeyabbotabceeabeamabearabeatabeerabeleabengabersabetsabeysabhorabideabiesabiusabjadabjudabledablerablesabletablowabmhoabnetabodeabohmaboilabomaaboonabordaboreabornabortaboutaboveabramabrayabrimabrinabrisabseyabsitabunaabuneaburaaburnabuseabutsabuzzabyesabysmabyssacaisacaraacariaccasacchaaccoyaccraacedyaceneacerbacersacetaacharachedacherachesacheyachooacidsacidyaciesacingaciniackeeackeracmesacmicacnedacnesacockacoelacoldaconeacornacralacredacresacridacronacrosacrylactasactedactinactonactoractusacuteacylsadageadaptadatsadawnadawsadaysadbotaddasaddaxaddedadderaddinaddioaddleaddraadeadadeemadeptadhanadhocadieuadiosaditsadlibadmanadmenadminadmitadmixadnexadobeadoboadoonadoptadorbadoreadornadownadozeadradadrawadredadretadripadsumadukiadultaduncadustadvewadvtsadytaadytsadzedadzesaeciaaedesaegeraegisaeonsaerieaerosaesiraevumafaldafancafaraafarsafearaffixafflyafionafireafizzaflajaflapaflowafoamafootaforeafoulafretafritafrosafteraftosagainagalsagamaagamiagamyagapeagarsagaspagastagateagatyagaveagazeagbasageneagentagersaggagaggeraggieaggriaggroaggryaghasagidiagilaagileagingagiosagismagistagitaagleeagletagleyaglooaglowaglusagmasagogeagogoagoneagonsagonyagoodagoraagreeagriaagrinagrosagrumaguedaguesagueyagunaagushagutiaheadaheapahentahighahindahingahintaholdaholeahullahuruaidasaidedaideraidesaidoiaidosaieryaigasaightailedaimagaimakaimedaimeraineeaingaaioliairedairerairnsairthairtsaisleaitchaitusaiveraixesaiyahaiyeeaiyohaiyooaizleajiesajivaajugaajupaajwanakaraakeesakelaakeneakingakitaakkasakkerakoiaakojaakoyaaksedaksesalaapalackalalaalamoalandalanealangalansalantalapaalapsalarmalaryalataalatealaysalbasalbeealbidalbumalceaalcesalcidalcosaldeaalderaldolaleakaleckalecsaleemalefsaleftalephalertalewsaleyealfasalgaealgalalgasalgidalginalgoralgosalgumaliasalibialickalienalifsalignalikealimsalinealiosalistalivealiyaalkiealkinalkosalkydalkylallanallayalleeallelallenalleralleyallinallisallodallotallowalloyallusallylalmahalmasalmehalmesalmudalmugalodsaloedaloesaloftalohaaloinalonealongaloofaloosalosealoudalowealphaaltaralteralthoaltosalulaalumsalumyalurealurkalvaralwayamahsamainamariamaroamassamateamautamazeambanamberambitambleambosambryamebaameeramendameneamensamentamiasamiceamiciamideamidoamidsamiesamigaamigoamineaminoaminsamirsamissamityamlasammanammasammonammosamniaamnicamnioamoksamoleamongamoreamortamouramoveamowtampedampleamplyampulamritamuckamuseamylsananaanataanchoancleanconandicandroanearaneleanentangasangelangerangleangloangryangstanighanileanilsanimaanimeanimianionaniseankerankhsankleankusanlasannalannanannasannatannexannoyannulannumannusanoasanodeanoleanomyansaeansasantaeantarantasantedantesanticantisantraantreantsyanuraanvilanyonaortaapaceapageapaidapartapaydapaysapeakapeekapersapertaperyapgaraphidaphisapianapingapiolapishapismapneaapodeapodsapolsapoopaportappalappamappayappelappleapplyapproapptsappuiappuyapresapronapsesapsisapsosaptedapteraptlyaquaeaquasarabaaraksarameararsarbaharbasarborarcedarchiarcosarcusardebardorardriareadareaearealarearareasarecaareddaredearefyareicarenaarenearepaarerearetearetsarettargalarganargilargleargolargonargotargueargusarhatariasarielarikiarilsariotarisearisharitharkedarledarlesarmedarmerarmetarmilarmorarnasarnisarnutarobaarohaaroidaromaarosearpasarpenarraharrasarrayarretarrisarrowarrozarsedarsesarseyarsisarsonartalartelarterarticartisartlyartsyaruhearumsarvalarveearvosarylsasadaasanaasconascotascusasdicashedashenashesashetasideasityaskaraskedaskeraskewaskoiaskosaspenasperaspicaspieaspisasproassaiassamassayassedassesassetassezassotasterastirastunasuraaswayaswimasylaatapsataxyatigiatiltatimyatlasatmanatmasatmosatocsatokeatoksatollatomsatomyatoneatonyatopyatriaatripattapattarattasatteratticatuasauchtaudadaudaxaudioauditaugenaugeraugesaughtauguraulasaulicauloiaulosaumilaunesauntsauntyauraeauralauraraurasaureiauresauricaurisaurumautosauxinavailavaleavantavastavelsavensaversavertavgasavianavineavionaviseavisoavizeavoidavowsavyzeawaitawakeawardawareawariawarnawashawatoawaveawaysawdlsaweelawetoawfulawingawkinawmryawnedawnerawokeawolsaworkaxelsaxialaxileaxilsaxingaxiomaxionaxiteaxledaxlesaxmanaxmenaxoidaxoneaxonsayahsayayaayelpaygreayinsaymagayontayresayrieazansazideazidoazineazlonazoicazoleazonsazoteazothazukiazureazurnazuryazygyazymeazymsbaaedbaalsbaapsbabasbabbybabelbabesbabkababoobabulbabusbaccabaccobaccybachabachsbacksbackybacnebaconbadambaddybadgebadlybaelsbaffsbaffybaftabaftsbagelbaggybaghsbagiebagsybaguabahtsbahusbahutbaiksbailebailsbairnbaisabaithbaitsbaizabaizebajanbajrabajribajusbakedbakenbakerbakesbakrabalasbaldsbaldybaledbalerbalesbalksbalkyballoballsballybalmsbalmybaloibalonbaloobalotbalsabaltibalunbalusbalutbamasbambibammabammybanakbanalbancobancsbandabandhbandsbandybanedbanesbangsbaniabanjobanksbankybannsbantsbantubantybantzbanyabaonsbaozibappubapusbarbebarbsbarbybarcabardebardobardsbardybaredbarerbaresbarfibarfsbarfybargebaricbarksbarkybarmsbarmybarnsbarnybaronbarpsbarrabarrebarrobarrybaryebasalbasanbasasbasedbasenbaserbasesbashabashobasicbasijbasilbasinbasisbasksbasonbassebassibassobassybastabastebastibastobastsbatchbatedbatesbathebathsbatikbatonbatosbattabattsbattubattybaudsbauksbaulkbaursbavinbawdsbawdybawksbawlsbawnsbawrsbawtybayasbayedbayerbayesbaylebayoubaytsbazarbazasbazoobballbdaysbeachbeadsbeadybeaksbeakybealsbeamsbeamybeanobeansbeanybeardbearebearsbeastbeathbeatsbeatybeausbeautbeauxbebopbecapbeckebecksbedadbedelbedesbedewbedimbedyebeechbeedibeefsbeefybeepsbeersbeerybeetsbefitbefogbegadbeganbegarbegatbegembegetbeginbegobbegotbegumbegunbeigebeigybeingbeinsbeirabeisabekahbelahbelarbelaybelchbeleebelgabeliebelitbellebellibellobellsbellybelonbelowbeltsbelvebemadbemasbemixbemudbenchbendsbendybenesbenetbengabenisbenjibennebennibennybentobentsbentybepatberayberesberetbergsberkoberksbermebermsberobberryberthberylbesatbesawbeseebesesbesetbesitbesombesotbestibestsbetasbetedbetelbetesbethsbetidbetonbettabettybevanbevelbeverbevorbevuebevvybewdybewetbewigbezelbezesbezilbezzybhaisbhajibhangbhatsbhavabhelsbhootbhunabhutsbiachbialibialybibbsbibesbibisbiblebiccybicepbicesbickybiddybidedbiderbidesbidetbidisbidonbidribieldbiersbiffobiffsbiffybifidbigaebiggsbiggybighabightbiglybigosbigotbihonbijoubikedbikerbikesbikiebikkybilalbilatbilbobilbybiledbilesbilgebilgybilksbillsbillybimahbimasbimbobinalbindibindsbinerbinesbingebingobingsbingybinitbinksbinkybintsbiogsbiomebionsbiontbiosebiotabipedbipodbippybirchbirdobirdsbirisbirksbirlebirlsbirosbirrsbirsebirsybirthbirzebirzzbisesbisksbisombisonbitchbiterbitesbiteybitosbitoubitsybittebittsbittybiviabivvybizesbizzobizzyblabsblackbladebladsbladyblaerblaesblaffblagsblahsblainblameblamsblancblandblankblareblartblaseblashblastblateblatsblattblaudblawnblawsblaysblazebleahbleakblearbleatblebsblechbleedbleepbleesblendblentblertblessblestbletsbleysblimpblimyblindblingbliniblinkblinsblinyblipsblissblistbliteblitsblitzblivebloatblobsblockblocsblogsblokeblondblonxbloodblookbloombloopbloreblotsblownblowsblowyblubsbludebludsbludybluedbluerbluesbluetblueybluffbluidblumeblunkbluntblurbblursblurtblushblypeboabsboaksboardboarsboartboastboatsboatybobacbobakbobasbobbybobolbobosboccabocceboccibochebocksbodedbodesbodgebodgybodhibodlebodohboepsboersboetiboetsboeufboffoboffsboganbogeyboggybogiebogleboguebogusboheabohosboilsboingboinkboitebokedbokehbokesbokosbolarbolasboldoboldsbolesboletbolixbolksbollsbolosboltsbolusbomasbombebombobombsbomohbomorboncebondsbonedbonerbonesboneybongobongsboniebonksbonnebonnybonumbonusbonzabonzebooaibooayboobsboobyboodybooedboofyboogyboohsbooksbookyboolsboomsboomyboongboonsboordboorsbooseboostboothbootsbootyboozeboozyboppyborakboralborasboraxbordebordsboredboreeborekborelborerboresborgoboricborksbormsbornaborneboronbortsbortybortzboseybosiebosksboskybosombosonbossabossybosunbotasbotchbotehbotelbotesbotewbothybotosbottebottsbottybougeboughbouksbouleboultboundbounsbourdbourgbournbousebousyboutsboutubovidbowatbowedbowelbowerbowesbowetbowiebowlsbownebowrsbowseboxedboxenboxerboxesboxlaboxtyboyarboyauboyedboyeyboyfsboygsboylaboylyboyosboysybozosbraaibracebrachbrackbractbradsbraesbragsbrahsbraidbrailbrainbrakebraksbrakybramebrandbranebrankbransbrantbrashbrassbrastbratsbravabravebravibravobrawlbrawnbrawsbraxybraysbrazabrazebreadbreakbreambredebredsbreedbreembreerbreesbreidbreisbremebrensbrentbrerebrersbrevebrewsbreysbriarbribebrickbridebriefbrierbriesbrigsbrikibriksbrillbrimsbrinebringbrinkbrinsbrinybriosbrisebriskbrissbrithbritsbrittbrizebroadbrochbrockbrodsbroghbrogsbroilbrokebromebromobroncbrondbroodbrookbroolbroombroosbrosebrosybrothbrownbrowsbruckbrughbruhsbruinbruitbrujabrujobrulebrumebrungbruntbrushbruskbrustbrutebrutsbruvsbuatsbuazebubalbubasbubbabubbebubbybubusbuchubuckobucksbuckubudasbuddybudedbudesbudgebudisbudosbuenabuffabuffebuffibuffobuffsbuffybufosbuftybuganbuggybuglebuhlsbuhrsbuiksbuildbuiltbuistbukesbukosbulbsbulgebulgybulksbulkybullabullsbullybulsebumbobumfsbumphbumpsbumpybunasbuncebunchbuncobundebundhbundsbundtbundubundybungsbungybuniabunjebunjybunkobunksbunnsbunnybuntsbuntybunyabuoysbuppyburanburasburbsburdsburetburfiburghburgsburinburkaburkeburksburlsburlyburnsburntburooburpsburqaburraburroburrsburrybursaburseburstbusbybusedbusesbushybusksbuskybussubustibustsbustybutchbuteobutesbutlebutohbuttebuttsbuttybututbutylbuxombuyerbuyinbuzzybwanabwazibydedbydesbykedbykesbylawbyresbyrlsbyssibytesbywaycaaedcabalcabascabbycabercabincablecabobcaboccabrecacaocacascachecackscackycacticaddycadeecadescadetcadgecadgycadiecadiscadrecaecacaesecafescaffecaffscagedcagercagescageycagotcahowcaidscainscairdcairncajoncajuncakedcakescakeycalfscalidcalifcalixcalkscallacallecallscalmscalmycaloscalpacalpscalvecalyxcamancamascamelcameocamescamiscamoscampicampocampscampycamuscanalcandocandycanedcanehcanercanescangscanidcannacannscannycanoecanoncansocanstcanticantocantscantycapascapaxcapedcapercapescapexcaphscapizcaplecaponcaposcapotcapricapulcaputcarapcaratcarbocarbscarbycardicardscardycaredcarercarescaretcarexcargocarkscarlecarlscarnecarnscarnycarobcarolcaromcaroncarpecarpicarpscarrscarrycarsecartacartecartscarvecarvycasascascocasedcasercasescaskscaskycastecastscasuscatchcatercatescattycaudacaukscauldcaulkcaulscaumscaupscauricausacausecavascavedcavelcavercavescaviecavilcavuscawedcawkscaxonceaseceazecebidcecalcecumcedarcededcedercedescedisceibaceiliceilscelebcellacellicellocellscellycelomceltscensecentocentscentuceorlcepescerciceredcerescergeceriacericcernecerocceroscertscertycessecestacesticetescetylcezvechaapchaatchacechackchacochadochadschafechaffchaftchainchairchaischalkchalschampchamschanachangchankchantchaoschapechapschaptcharachardcharecharkcharmcharrcharschartcharychasechasmchatschavachavechavschawkchawlchawschayachayscheapcheatchebacheckchedicheebcheekcheepcheercheetchefschekachelachelpchemochemscherechertchesschestchethchevychewschewychiaochiaschibachibschicachichchickchicochicschidechiefchielchikochikschildchilechilichillchimbchimechimochimpchinachinechingchinkchinochinschipschirkchirlchirmchirochirpchirrchirtchiruchitichitschivachivechivschivychizzchockchocochocschodechogschoilchoirchokechokochokycholacholicholochompchonschoofchookchoomchoonchopschordchorechosechosschotachottchoutchouxchowkchowschubschuckchufachuffchugschumpchumschunkchurlchurnchurrchusechutechutschylechymechyndcibolcidedcidercidescielscigarciggyciliacillscimarcimexcinchcinctcinescinqscionscippicircacircscirescirlscirriciscocissycistscitalcitedciteecitercitescivescivetcivicciviecivilcivvyclachclackcladecladsclaesclagsclaimclairclameclampclamsclangclankclansclapsclaptclaroclartclaryclashclaspclassclastclatsclautclaveclaviclawsclayscleanclearcleatcleckcleekcleepclefscleftclegscleikclemsclepecleptclerkcleveclewsclickcliedcliescliffcliftclimbclimeclineclingclinkclintclipeclipscliptclitscloakcloamclockclodscloffclogsclokeclombclompcloneclonkclonscloopclootclopsclosecloteclothclotscloudclourclouscloutcloveclownclowscloyecloysclozeclubscluckcluedcluesclueyclumpclungclunkclypecnidacoachcoactcoadycoalacoalscoalycoaptcoarbcoastcoatecoaticoatscobbscobbycobiacoblecobotcobracobzacocascoccicoccocockscockycocoacocoscocuscodascodeccodedcodencodercodescodexcodoncoedscoffscogiecogoncoguecohabcohencohoecohogcohoscoifscoigncoilscoinscoirscoitscokedcokescokeycolascolbycoldscoledcolescoleycoliccolincollecollscollycologcoloncolorcoltscolzacomaecomalcomascombecombicombocombscombycomercomescometcomfycomiccomixcommacommecommocommscommycompocompscomptcomtecomusconchcondoconedconesconexconeyconfscongacongecongoconiaconicconinconksconkyconneconnscontecontoconusconvocoochcooedcooeecooercooeycoofscookscookycoolscoolycoombcoomscoomycoonscoopscooptcoostcootscootycoozecopalcopaycopedcopencopercopescophacoppycopracopsecopsycoquicoralcoramcorbecorbycordacordscoredcorercorescoreycorgicoriacorkscorkycormscornicornocornscornucornycorpscorsecorsocoseccosedcosescosetcoseycosiecostacostecostscotancotchcotedcotescothscottacottscouchcoudecoughcouldcountcoupecoupscourbcourdcourecourscourtcoutacouthcovedcovencovercovescovetcoveycovincowalcowancowedcowercowkscowlscowpscowrycoxaecoxalcoxedcoxescoxibcoyaucoyedcoyercoylycoypucozedcozencozescozeycoziecraalcrabscrackcraftcragscraiccraigcrakecramecrampcramscranecrankcranscrapecrapscrapycrarecrashcrasscratecravecrawlcrawscrayscrazecrazycreakcreamcredocredscreedcreekcreelcreepcreescreincremacremecremscrenacrepecrepscreptcrepycresscrestcrewecrewscriascribocribscrickcriedcriercriescrimecrimpcrimscrinecrinkcrinscrioscripecripscrisecrispcrisscrithcritscroakcrocicrockcrocscroftcrogscrombcromecronecronkcronscronycrookcroolcrooncropscrorecrosscrostcroupcroutcrowdcrowlcrowncrowscrozecruckcrudecrudocrudscrudycruelcruescruetcruftcrumbcrumpcrunkcruorcruracrusecrushcrustcrusycruvecrwthcryercrynecryptctenecubbycubebcubedcubercubescubiccubitcuckscuddacuddycuecacuffocuffscuifscuingcuishcuitscukesculchculetculexcullscullyculmsculpaculticultscultycumeccumincundycuneicunitcunnycuntscupelcupidcuppacuppycuprocuratcurbscurchcurdscurdycuredcurercurescuretcurfscuriacuriecuriocurlicurlscurlycurnscurnycurrscurrycursecursicurstcurvecurvycuseccushycuskscuspscuspycussocusumcutchcutercutescuteycutiecutincutiscuttocuttycutupcuveecuzescwtchcyanocyanscybercycadcycascyclecyclocydercylixcymaecymarcymascymescymolcyniccystscytescytonczarsdaalsdabbadacesdachadacksdadahdadasdaddydadisdadladadosdaffsdaffydaggadaggydagosdahisdahlsdaikodailydainedaintdairydaisydakerdaleddalekdalesdalisdalledallydaltsdamandamardamesdammedamnadamnsdampsdampydancedancydandadandydangsdaniodanksdannydansedantsdappydarafdarbsdarcydareddarerdaresdargadargsdaricdarisdarksdarkydarlsdarnsdarredartsdarzidashidashydataldateddaterdatesdatildatosdattodatumdaubedaubsdaubydaudsdaultdauntdaursdautsdavendavitdawahdawdsdaweddawendawgsdawksdawnsdawtsdayaldayandaychdayntdazeddazerdazesdbagsdeadsdeairdealsdealtdeansdearedearndearsdearydeashdeathdeavedeawsdeawydebagdebardebbydebeldebesdebitdebtsdebuddebugdeburdebusdebutdebyedecaddecafdecaldecandecaydecimdeckodecksdecordecosdecoydecrydecyldedaldeedsdeedydeelydeemsdeensdeepsdeeredeersdeetsdeevedeevsdefatdeferdeffodefisdefogdegasdegumdegusdeicedeidsdeifydeigndeilsdeinkdeismdeistdeitydekeddekesdekkodelaydeleddelesdelfsdelftdelisdelladellsdellydelosdelphdeltadeltsdelvedemandemesdemicdemitdemobdemoidemondemosdemotdemptdemurdenardenaydenchdenesdenetdenimdenisdensedentedentsdeochdeoxydepotdepthderatderayderbyderedderesderigdermadermsdernsdernyderosderpyderroderryderthdervsdesexdeshidesisdesksdessedetagdeterdetoxdeucedevasdeveldevildevisdevondevosdevotdewandewardewaxdeweddexesdexiedexysdhabadhaksdhalsdhikrdhobidholedholldholsdhonidhotidhowsdhutidiactdialsdianadianediarydiazodibbsdiceddicerdicesdiceydichtdicksdickydicotdictadictodictsdictudictydiddydidiedidisdidosdidstdiebsdielsdienedietsdiffsdightdigitdikasdikeddikerdikesdikeydildodillidillsdillydimbodimerdimesdimlydimpsdinardineddinerdinesdingedingodingsdingydinicdinksdinkydinlodinnadinosdintsdiochdiodediolsdiotadippydipsodiramdirerdirgedirkedirksdirlsdirtsdirtydisasdiscidiscodiscsdishydisksdismeditalditasditchditedditesditsydittodittsdittyditzydivandivasdiveddiverdivesdiveydivisdivnadivosdivotdivvydiwandixiedixitdiyasdizendizzydjinndjinsdoabsdoatsdobbydobesdobiedobladobledobradobrodochtdocksdocosdocusdoddydodgedodgydodosdoeksdoersdoestdoethdoffsdogaldogandogesdogeydoggodoggydogiedoglydogmadohyodoiltdoilydoingdoitsdojosdolcedolcidoleddoleedolesdoleydoliadoliedollsdollydolmadolordolosdoltsdomaldomeddomesdomicdonahdonasdoneedonerdongadongsdonkodonnadonnedonnydonordonsydonutdoobsdoocedoodydoofsdooksdookydooledoolsdoolydoomsdoomydoonadoorndoorsdoozydopasdopeddoperdopesdopeydoppedoraddorbadorbsdoreedoresdoricdorisdorjedorksdorkydormsdormydorpsdorrsdorsadorsedortsdortydosaidosasdoseddosehdoserdosesdoshadotaldoteddoterdotesdottydouardoubtdoucedoucsdoughdouksdouladoumadoumsdoupsdouradousedoutsdoveddovendoverdovesdoviedowakdowardowdsdowdydoweddoweldowerdowfsdowiedowledowlsdowlydownadownsdownydowpsdowrydowsedowtsdoxeddoxesdoxiedoyendoylydozeddozendozerdozesdrabsdrackdracodraffdraftdragsdraildraindrakedramadramsdrankdrantdrapedrapsdrapydratsdravedrawldrawndrawsdraysdreaddreamdreardreckdreeddreerdreesdregsdreksdrentdreredressdrestdreysdribsdricedrieddrierdriesdriftdrilldrilydrinkdripsdriptdrivedrockdroiddroildroitdrokedroledrolldromedronedronydroobdroogdrookdrooldroopdropsdroptdrossdroukdrovedrowndrowsdrubsdrugsdruiddrumsdrunkdrupedrusedrusydruxydryaddryasdryerdrylydsobodsomoduadsdualsduansduarsdubbodubbyducalducatducesduchyducksduckyductiductsduddydudeddudesduelsduetsduettduffsdufusduingduitsdukasdukeddukesdukkadukundulcedulesduliadullsdullydulsedumasdumbodumbsdumkadumkydummydumpsdumpydunamduncedunchdunesdungsdungydunksdunnodunnydunshduntsduomiduomodupedduperdupesdupleduplyduppyduraldurasduredduresdurgydurnsdurocdurosduroydurradurrsdurrydurstdurumdurzidusksduskydustsdustydutchduvetduxesdwaaldwaledwalmdwamsdwamydwangdwarfdwaumdweebdwelldweltdwiledwinedyadsdyersdyingdykeddykesdykeydykondyneldynesdynosdzhoseagereagleeaglyeagreealedealeseanedeardsearedearlsearlyearnsearntearsteartheasedeaseleasereaseseasleeastseateneatereatheeatineavedeavereavesebankebbedebbetebenaebeneebikeebonsebonyebookecadsecardecashechedechesechosecigseclatecoleecrusedemaedgededgeredgesedictedifyedileeditseduceeducteejiteensyeerieeeveneevereevnseffedefferefitsegadsegersegesteggareggedeggeregmasegretehingeidereidoseighteigneeikedeikoneildseironeiselejectejidoekdamekingekkaselainelandelanselateelbowelchieldereldinelecteleetelegyelemielfedelfineliadelideelinteliteelmenelogeelogyeloinelopeelopselpeeelsineludeeluteelvanelvenelverelvesemacsemailembarembayembedemberembogembowemboxembusemceeemeeremendemergemeryemeusemicsemirsemitsemmasemmeremmetemmewemmysemojiemongemoteemoveemptsemptyemuleemureemydeemydsenactenarmenateendedenderendewendowendueenemaenemyenewsenfixeniacenjoyenlitenmewennogennuienokienolsenormenowsenrolensewenskyensueenterentiaentreentryenureenurnenvoienvoyenzymeolideorlseosinepactepeesepenaepeneephahephasephodephorepicsepochepodeepoptepoxyeppieeprisequalequesequidequiperaseerbiaerecterevsergonergosergoterhusericaerickericseringernederneserodeeroseerrederrorerseseructerugoerupteruvservenervilescarescotesileeskareskeresnesesrogessayessesesterestocestopestroetageetapeetatsetensethaletherethicethneethosethyleticsetnasetrogettinettleetudeetuisetweeetymaeughseukedeupadeuroseusolevadeevegsevenseventeverteveryevetsevhoeevictevilseviteevoheevokeewersewestewhowewkedexactexaltexamsexcelexeatexecsexeemexemeexertexfilexierexiesexileexineexingexistexiteexitsexodeexomeexonsexpatexpelexposextolextraexudeexulsexultexurbeyasseyerseyingeyotseyraseyreseyrieeyrirezinefabbofabbyfablefacedfacerfacesfacetfaceyfaciafaciefactafactofactsfactyfaddyfadedfaderfadesfadgefadosfaenafaeryfaffsfaffyfaggyfaginfagotfaiksfailsfainefainsfaintfairefairsfairyfaithfakedfakerfakesfakeyfakiefakirfalajfalesfallsfalsefalsyfamedfamesfanalfancyfandsfanesfangafangofangsfanksfannyfanonfanosfanumfaqirfaradfarcefarcifarcyfardsfaredfarerfaresfarlefarlsfarmsfarosfarrofarsefartsfascifastifastsfatalfatedfatesfatlyfatsofattyfatwafauchfaughfauldfaultfaunafaunsfaurdfautefautsfauvefavasfavelfaverfavesfavorfavusfawnsfawnyfaxedfaxesfayedfayerfaynefayrefazedfazesfealsfeardfearefearsfeartfeasefeastfeatsfeazefecalfecesfechtfecitfecksfedaifedexfeebsfeedsfeelsfeelyfeensfeersfeesefeezefehmefeignfeintfeistfelchfelidfelixfellafellsfellyfelonfeltsfeltyfemalfemesfemicfemmefemmyfemurfencefendsfendyfenisfenksfennyfentsfeodsfeoffferalfererferesferiaferlyfermifermsfernsfernyferoxferryfessefestafestsfestyfetalfetasfetchfetedfetesfetidfetorfettafettsfetusfetwafeuarfeudsfeuedfeverfewerfeyedfeyerfeylyfezesfezzyfiarsfiatsfiberfibrefibroficesfichefichuficinficosfictaficusfidesfidgefidosfidusfiefsfieldfiendfientfierefierifiersfieryfiestfifedfiferfifesfifisfifthfiftyfiggyfightfigosfikedfikesfilarfilchfiledfilerfilesfiletfiliifilksfillefillofillsfillyfilmifilmsfilmyfilonfilosfilthfilumfinalfincafinchfindsfinedfinerfinesfinisfinksfinnyfinosfiordfiqhsfiquefiredfirerfiresfiriefirksfirmafirmsfirnifirnsfirryfirstfirthfiscsfishofishyfisksfistsfistyfitchfitlyfitnafittefittsfiverfivesfixedfixerfixesfixiefixitfizzyfjeldfjordflabsflackflaffflagsflailflairflakeflaksflakyflameflammflamsflamyflaneflankflansflapsflareflaryflashflaskflatsflavaflawnflawsflawyflaxyflaysfleamfleasfleckfleekfleerfleesfleetflegsflemefleshfleurflewsflexiflexofleysflickflicsfliedflierfliesflimpflimsflingflintflipsflirsflirtfliskfliteflitsflittfloatflobsflockflocsfloesflogsflongfloodfloorflopsflorafloreflorsfloryfloshflossflotafloteflourfloutflownflowsflowyflubsfluedfluesflueyflufffluidflukeflukyflumeflumpflungflunkfluorflurrflushfluteflutyfluytflybyflyerflyinflypeflytefnarrfoalsfoamsfoamyfocalfocusfoehnfogeyfoggyfogiefoglefogosfogoufohnsfoidsfoilsfoinsfoistfoldsfoleyfoliafolicfoliefoliofolksfolkyfollyfomesfondafondsfondufonesfoniofonlyfontsfoodsfoodyfoolsfootsfootyforamforayforbsforbyforcefordofordsforelforesforexforgeforgoforksforkyformaformeformsforteforthfortsfortyforumforzaforzefossafossefouatfoudsfouerfouetfoulefoulsfoundfountfoursfouthfoveafowlsfowthfoxedfoxesfoxiefoyerfoylefoynefrabsfrackfractfragsfrailfraimfraisframefrancfrankfrapefrapsfrassfratefratifratsfraudfrausfraysfreakfreedfreerfreesfreetfreitfremdfrenafreonfrerefreshfretsfriarfribsfriedfrierfriesfrigsfrillfrisefriskfristfritafritefrithfritsfrittfritzfrizefrizzfrockfroesfrogsfrommfrondfronsfrontfroomfrorefrornfroryfroshfrostfrothfrownfrowsfrowyfroyofrozefrugsfruitfrumpfrushfrustfryerfubarfubbyfubsyfucksfucusfuddyfudgefudgyfuelsfuerofuffsfuffyfugalfuggyfugiefugiofugisfuglefuglyfuguefugusfujisfullafullsfullyfulthfulwafumedfumerfumesfumetfundafundifundofundsfundyfungifungofungsfunicfunisfunksfunkyfunnyfunsyfuntsfuralfuranfurcafurlsfurolfurorfurosfurrsfurryfurthfurzefurzyfusedfuseefuselfusesfusilfusksfussyfustsfustyfutonfuzedfuzeefuzesfuzilfuzzyfycesfykedfykesfylesfyrdsfyttegabbagabbygablegaddigadesgadgegadgygadidgadisgadjegadjogadsogaffegaffsgagedgagergagesgaidsgailygainsgairsgaitagaitsgaittgajosgalahgalasgalaxgaleagaledgalesgaliagalisgallsgallygalopgalutgalvogamasgamaygambagambegambogambsgamedgamergamesgameygamicgamingammagammegammygampsgamutganchgandyganefganevgangsganjaganksganofgantsgaolsgapedgapergapesgaposgappygaramgarbagarbegarbogarbsgardagardegaresgarisgarmsgarnigarregarrigarthgarumgasesgashygaspsgaspygassygastsgatchgatedgatergatesgathsgatorgauchgaucygaudsgaudygaugegaujegaultgaumsgaumygauntgaupsgaursgaussgauzegauzygavelgavotgawcygawdsgawksgawkygawpsgawsygayalgayergaylygazalgazargazedgazergazesgazongazoogealsgeansgearegearsgeasageatsgeburgeckogecksgeeksgeekygeepsgeesegeestgeistgeitsgeldsgeleegelidgellygeltsgemelgemmagemmygemotgenaegenalgenasgenesgenetgenicgeniegeniigeningeniogenipgennygenoagenomgenregenrogentsgentygenuagenusgeodegeoidgerahgerbegeresgerlegermsgermygernegessegessogestegestsgetasgetupgeumsgeyangeyerghastghatsghautghazigheesghestghostghoulghuslghyllgiantgibedgibelgibergibesgibligibusgiddygiftsgigasgighegigotgiguegilasgildsgiletgiliagillsgillygilpygiltsgimelgimmegimpsgimpyginchgingagingegingsginksginnyginzogipongippogippygipsygirdsgirlfgirlsgirlygirnsgirongirosgirrsgirshgirthgirtsgismogismsgistsgitchgitesgiustgivedgivengivergivesgizmoglacegladegladsgladyglaikglairglampglamsglandglansglareglaryglassglattglaumglaurglazeglazygleamgleanglebaglebeglebygledegledsgleedgleekgleesgleetgleisglensglentgleysglialgliasglibsglidegliffgliftglikeglimeglimsglintgliskglitsglitzgloamgloatglobeglobiglobsglobyglodegloggglomsgloomgloopglopsgloryglossglostgloutgloveglowsglowyglozegluedgluergluesglueygluggglugsglumeglumsgluongluteglutsglyphgnapignarlgnarrgnarsgnashgnatsgnawngnawsgnomegnowsgoadsgoafsgoaftgoalsgoarygoatsgoatygoavegobangobargobbegobbigobbogobbygobisgobosgodetgodlygodsogoelsgoersgoestgoethgoetygofergoffsgoggagogosgoiergoinggojisgokesgoldsgoldygolemgolesgolfsgollygolpegolpsgombogomergompagonadgonchgonefgonergongsgoniagonifgonksgonnagonofgonysgonzogoobygoodogoodsgoodygooeygoofsgoofygoogsgooksgookygooldgoolsgoolygoomygoonsgoonygoopsgoopygoorsgoorygoosegoosygopakgopikgoralgorasgoraygorbsgordogoredgoresgorgegorisgormsgormygorpsgorsegorsygoshtgossegotchgothsgothygottagouchgougegouksgouragourdgoutsgoutygovedgovesgowangowdsgowfsgowksgowlsgownsgoxesgoyimgoylegraalgrabsgracegradegradsgraffgraftgrailgraingraipgramagramegrampgramsgranagrandgranogransgrantgrapegraphgrapygraspgrassgratagrategratsgravegravsgravygraysgrazegreatgrebegrebogrecegreedgreekgreengreesgreetgregegregogreingrensgrepsgresegrevegrewsgreysgricegridegridsgriefgriffgriftgrigsgrikegrillgrimegrimygrindgrinsgriotgripegripsgriptgripygrisegristgrisygrithgritsgrizegroangroatgrodygrogsgroingroksgromagromsgronegroofgroomgropegrossgroszgrotsgroufgroupgroutgrovegrovygrowlgrowngrowsgrrlsgrrrlgrubsgruedgruelgruesgrufegruffgrumegrumpgrundgruntgrycegrydegrykegrypegryptguacoguanaguanoguansguardguarsguavagubbagucksguckygudesguessguestguffsgugasgugglguideguidoguidsguildguileguiltguimpguiroguisegulabgulaggulargulasgulchgulesguletgulfsgulfygullsgullygulphgulpsgulpygumbogummagummigummygumpsgunasgundigundygungegungygunksgunkygunnyguppyguqingurdygurgegurksgurlsgurlygurnsgurrygurshgurusgushyguslaguslegusligussygustogustsgustygutsyguttaguttyguyedguyleguyotguysegwinegyalsgyansgybedgybesgyeldgympsgynaegyniegynnygynosgyozagypesgyposgyppogyppygypsygyralgyredgyresgyrongyrosgyrusgytesgyvedgyvergyveshaafshaarshaatshabithablehabushacekhackshackyhadalhadedhadeshadjihadsthaemshaerehaetshaffshafizhaftahaftshaggshahamhahashaickhaikahaikshaikuhailshailyhainshainthairshairyhaithhajeshajishajjihakamhakashakeahakeshakimhakushalalhaldihaledhalerhaleshalfahalfshalidhallohallshalmahalmshalonhaloshalsehalshhaltshalvahalvehalwahamalhambahamedhamelhameshammyhamzahanaphancehanchhandihandshandyhangihangshankshankyhansahansehantshaolehaomahapashapaxhaplyhappihappyhapusharamhardshardyharedharemharesharimharksharlsharmsharnsharosharpsharpyharryharshhartshashyhaskshaspshastahastehastyhatchhatedhaterhateshathahathihattyhaudshaufshaughhaugohauldhaulmhaulshaulthaunshaunthausehautehavanhavelhavenhaverhaveshavochawedhawkshawmshawsehayedhayerhayeyhaylehazanhazedhazelhazerhazeshazleheadsheadyhealdhealsheameheapsheapyheardhearehearsheartheastheathheatsheatyheaveheavyhebenhebeshechtheckshederhedgehedgyheedsheedyheelsheezehefteheftsheftyheiauheidsheighheilsheirsheisthejabhejraheledhelesheliohelixhellahellohellshellyhelmsheloshelothelpshelvehemalhemeshemicheminhempshempyhencehenchhendshengehennahennyhenryhentsheparherbsherbyherdsheresherlshermahermshernsheronherosherpsherryhersehertzheryehespshestsheteshethsheuchheughheveahevelhewedhewerhewghhexadhexedhexerhexeshexylheyedhianthibashickshidedhiderhideshiemshifishighshighthijabhijrahikedhikerhikeshikoihilarhilchhillohillshillyhilsahiltshilumhilushimbohinauhindshingehingshinkyhinnyhintshioishipedhiperhipeshiplyhippohippyhiredhireehirerhireshissyhistshitchhithehivedhiverhiveshizenhoachhoaedhoagyhoardhoarshoaryhoasthobbyhoboshockshocushodadhodjahoershoganhogenhoggshoghshogohhogoshohedhoickhoiedhoikshoinghoisehoisthokashokedhokeshokeyhokishokkuhokumholdsholedholesholeyholkshollahollohollyholmeholmsholonholosholtshomashomedhomerhomeshomeyhomiehommehomoshonanhondahondshonedhonerhoneshoneyhongihongshonkshonkyhonorhoochhoodshoodyhooeyhoofshoogohoohahookahookshookyhoolyhoonshoopshoordhoorshooshhootshootyhoovehopakhopedhoperhopeshoppyhorahhoralhorashordehorishorkshormehornshornyhorsehorsthorsyhosedhoselhosenhoserhoseshoseyhostahostshotchhotelhotenhotishotlyhottehottyhouffhoufshoughhoundhourihourshousehoutshoveahovedhovelhovenhoverhoveshowayhowbehowdyhoweshowffhowfshowkshowlshowrehowsohowtohoxedhoxeshoyashoyedhoylehubbahubbyhuckshudnahududhuershuffshuffyhugerhuggyhuhushuiashuieshukouhulashuleshulkshulkyhullohullshullyhumanhumashumfshumichumidhumorhumphhumpshumpyhumushunchhundohunkshunkyhuntshurdshurlshurlyhurrahurryhursthurtshurtyhushyhuskshuskyhusoshussyhutchhutiahuzzahuzzyhwylshydelhydrahydrohyenahyenshyggehyinghykeshylashyleghyleshylichymenhymnshyndehyoidhypedhyperhypeshyphahyphyhyposhyraxhysonhytheiambiiambsibrikicersichedichesichoriciericilyicingickerickleiconsictalicticictusidantiddahiddatiddutidealideasideesidentidiomidiotidledidleridlesidlisidolaidolsidyllidylsiftarigapoiggediglooiglusignisihramiiwisikansikatsikonsileacilealileumileusiliaciliadilialiliumillerillthimageimagoimagyimamsimariimaumimbarimbedimbosimbueimideimidoimidsimineiminoimlisimmewimmitimmiximpedimpelimpisimplyimpotimproimshiimshyinaneinaptinarminboxinbyeincasincelincleincogincurincusincutindewindexindiaindieindolindowindriindueineptinerminertinferinfixinfosinfrainganingleingotinioninkedinkerinkleinlayinletinnedinnerinnieinnitinorbinputinrosinruninseeinsetinspointelinterintilintisintraintroinulainureinurninustinvarinverinwitiodiciodidiodinioniciorasiotasipponiradeirateiridsiringirkedirokoironeironsironyisbasishesisledislesisletisnaeisseiissueistleitchyitemsitheriviediviesivoryixiasixnayixoraixtleizardizarsizzatjaapsjabotjacaljacetjacksjackyjadedjadesjafasjaffajagasjagerjaggsjaggyjagirjagrajailsjakerjakesjakeyjakiejalapjaleojalopjambejambojambsjambujamesjammyjamonjamunjanesjankyjannsjannyjantyjapanjapedjaperjapesjarksjarlsjarpsjartajaruljaseyjaspejaspsjathajatisjatosjauksjaunejauntjaupsjavasjaveljawanjawedjawnsjaxiejazzyjeansjeatsjebeljedisjeelsjeelyjeepsjeerajeersjeezejefesjeffsjehadjehusjelabjellojellsjellyjembejemmyjennyjeonsjeridjerksjerkyjerryjessejessyjestsjesusjeteejetesjetonjettyjeunejewedjeweljewiejhalajheeljhilsjiaosjibbajibbsjibedjiberjibesjiffsjiffyjiggyjigotjihadjillsjiltsjimmyjimpyjingojingsjinksjinnejinnijinnsjirdsjirgajirrejismsjitisjittyjivedjiverjivesjiveyjnanajobedjobesjockojocksjockyjocosjodeljoeysjohnsjoinsjointjoistjokedjokerjokesjokeyjokoljoledjolesjoliejollojollsjollyjoltsjoltyjomonjomosjonesjongsjontyjooksjoramjortsjorumjotasjottyjotunjoualjougsjouksjoulejoursjoustjowarjowedjowlsjowlyjoyedjubasjubesjucosjudasjudgejudgyjudosjugaljugumjuicejuicyjujusjukedjukesjukusjulepjuliajumarjumbojumbyjumpsjumpyjuncojunksjunkyjuntajuntojupesjuponjuraljuratjureljuresjurisjurorjustejustsjutesjuttyjuvesjuviekaamakababkabarkabobkachakackskadaikadeskadiskafirkagoskaguskahalkaiakkaidskaieskaifskaikakaikskailskaimskaingkainskajalkakaskakiskalamkalaskaleskalifkaliskalpakaluakamaskameskamikkamiskammekanaekanalkanaskanatkandykanehkaneskangakangskanjikantskanzukaonskapaikapaskaphakaphskapokkapowkappakapurkapuskaputkaraikaraskaratkareekarezkarkskarmakarnskarookaroskarrikarstkarsykartskarzykashakasmekatalkataskatiskattikaughkaurikaurukaurykavalkavaskawaskawaukawedkayakkaylekayoskaziskazookbarskcalskeakikebabkebarkebobkeckskedgekedgykeechkeefskeekskeelskeemakeenokeenskeepskeetskeevekefirkehuakeirskelepkelimkellskellykelpskelpykeltskeltykembokembskempskemptkempykenafkenchkendokenoskentekentskepiskerbskerelkerfskerkykermakernekernskeroskerrykervekesarkestsketasketchketesketolkevelkevilkexeskeyedkeyerkhadikhadskhafskhakikhanakhanskhaphkhatskhayakhazikhedakheerkhethkhetskhirskhojakhorskhoumkhudskhulakhyalkiaatkiackkiakikiangkiasukibbekibbikibeikibeskiblakickskickykiddokiddykidelkideokidgekiefskierskievekievskightkikaykikeskikoikileykiligkilimkillskilnskiloskilpskiltskiltykimbokimetkinaskindakindskindykineskingskingykininkinkskinkykinoskiorekioskkipahkipaskipeskippakippskipsykirbykirkskirnskirrikisankissykistskitabkitedkiterkiteskithekithskitkekittykitulkivaskiwisklangklapsklettklickkliegkliksklongkloofklugeklutzknackknagsknapsknarlknarsknaurknaveknawekneadkneedkneelkneesknellkneltknickknifeknishknitskniveknobsknockknollknoopknopsknospknotsknoudknoutknowdknoweknownknowsknubsknuleknurlknurrknursknutskoalakoanskoapskobankoboskoelskoffskoftakogalkohaskohenkohlskoinekoiwikojiskokamkokaskokerkokrakokumkolaskoloskombikombukonbukondokonkskookskookykoorikopekkophskopjekoppakoraikorankoraskoratkoreskoriskormakoroskorunkoruskoseskotchkotoskotowkourakraalkrabskraftkraiskraitkrangkranskranzkrautkrayskreefkreenkreepkrengkrewekrillkriolkronakronekroonkrubikrumpkrunkksarskubiekudoskuduskudzukufiskugelkuiaskukrikukuskulakkulankulaskulfikumiskumyskunaskundskuriskurrekurtakuruskussokustikutaikutaskutchkutiskutuskuyaskuzuskvasskvellkwaaikwelakwinkkwirlkyackkyakskyangkyarskyatskyboskydstkyleskyliekylinkylixkyloekyndekyndskypeskyriekyteskythekyudolaarflaarilabdalabellabialabislabnelaborlabralaccylacedlacerlaceslacetlaceylacislackalackslackyladduladdyladedladeeladenladerladesladleladoolaerslaevolaganlagarlagerlaggylahallaharlaichlaicslaidelaidslaighlaikalaikslairdlairslairylaithlaitylakedlakerlakeslakhslakinlaksalaldylallslamaslambslambylamedlamerlameslamialammylampslanailanaslancelanchlandelandslanedlaneslankslankylantslapaslapellapinlapislapjelappalappylapselarchlardslardylareelareslarfslargalargelargolarislarkslarkylarnslarntlarumlarvalasedlaserlaseslassilassolassulassylastslatahlatchlatedlatenlaterlatexlathelathilathslathylatkelattelatuslauanlauchlaudelaudslaufslaughlaundlauralavallavaslavedlaverlaveslavralavvylawedlawerlawinlawkslawnslawnylawsylaxedlaxerlaxeslaxlylaybylayedlayerlayinlayuplazarlazedlazeslazoslazzilazzoleachleadsleadyleafsleafyleaksleakyleamsleansleantleanyleapsleaptlearelearnlearslearyleaseleashleastleatsleaveleavyleazelebenleccylecheledesledgeledgyledumleearleechleeksleepsleersleeryleeseleetsleezelefteleftsleftylegallegerlegesleggeleggoleggylegitlegnolehrslehualeirsleishlemanlemedlemellemeslemmalemmelemonlemurlendsleneslengslenislenoslenselentilentoleonelepakleperlepidlepraleptaleredlereslerpslesboleseslesoslestsletchlethelettyletupleuchleucoleudsleughlevasleveelevelleverleveslevinlevislewislexeslexislezeslezzalezzolezzylianalianeliangliardliarsliartlibelliberliborlibralibrelibrilicetlichilichtlicitlickslidarlidosliefsliegelienslierslieuslieveliferlifeslifeyliftsliganligerliggelightlignelikedlikenlikerlikeslikinlilaclillslilosliltsliltylimanlimaslimaxlimbalimbilimbolimbslimbylimedlimenlimeslimeylimitlimmalimnslimoslimpalimpslinaclinchlindslindylinedlinenlinerlineslineylingalingolingslingylininlinkslinkylinnslinnylinoslintslintylinumlinuxlionslipaslipeslipidlipinliposlippyliraslirkslirotlisesliskslislelispslistslitailitaslitedlitemliterliteslithelitholithslitielitrelivedlivenliverliveslividlivorlivreliwaaliwasllamallanoloachloadsloafsloamsloamyloansloastloathloavelobarlobbylobedlobesloboslobuslocallochelochslochylocielocislockslockylocoslocumlocuslodenlodeslodgeloessloftsloftyloganlogesloggylogialogiclogieloginlogoilogonlogoslohanloidsloinsloipeloirslokeslokeylokumlolasloledlollolollslollylologloloslomaslomedlomeslonerlongalongelongsloobylooedlooeyloofaloofslooielookslookyloomsloonsloonyloopsloopyloordlooselootslopedloperlopesloppyloralloranlordslordylorelloresloriclorislorrylosedlosellosenloserloseslossylotahlotaslotesloticlotoslotsalottalottelottolotuslouedloughlouielouisloumaloundlounsloupeloupslourelourslourylouselousyloutslovatlovedloveeloverlovesloveylovielowanlowedlowenlowerloweslowlylowndlownelownslowpslowrylowselowthlowtsloxedloxesloyallozenluachluauslubedlubeslubraluceslucidlucksluckylucreludesludicludosluffaluffslugedlugerlugeslullsluluslumaslumbilumenlummelummylumpslumpylunarlunaslunchluneslunetlungelungilungslunksluntslupinlupuslurchluredlurerlureslurexlurgilurgyluridlurkslurrylurveluserlushyluskslustslustylususlutealutedluterlutesluvvyluxedluxerluxeslweislyamslyardlyartlyaselycealyceelycralyinglymeslymphlynchlyneslyreslyriclysedlyseslysinlysislysollyssalytedlyteslythelyticlyttamaaedmaaremaarsmabanmabesmacasmacawmaccamacedmacermacesmachemachimachomachsmackamacksmaclemaconmacromactemadalmadammadarmaddymadgemadidmadlymadosmadremaedimaerlmafiamaficmaftsmagasmagesmaggsmagicmagmamagnamagotmagusmahalmahemmahismahoemahrsmahuamahwamaidsmaikomaiksmailemaillmailomailsmaimsmainsmairemairsmaisemaistmaizemajasmajatmajoemajormajosmakafmakaimakanmakarmakeemakermakesmakiemakismakosmalaemalaimalammalarmalasmalaxmaleomalesmalicmalikmalismalkymallsmalmsmalmymaltsmaltymalusmalvamalwamamakmamasmambamambomambumameemameymamiemamilmammamammymanasmanatmandimandsmandymanebmanedmanehmanesmanetmangamangemangimangomangsmangymaniamanicmaniemanismanksmankymanlymannamannymanoamanormanosmansemansomantamantemantomantsmantymanulmanusmanzomapaumapesmaplemapoumappymaqammaquimaraemarahmaralmaranmarasmaraymarchmarcsmardsmardymaresmargamargemargomargsmariamaridmarilmarkamarksmarlemarlsmarlymarmamarmsmaronmarormarramarrimarrymarsemarshmartsmaruamarvymasasmasedmasermasesmashamashymasksmasonmassamassemassymastsmastymasurmasusmasutmataimatchmatedmatermatesmateymathemathsmatinmatlomatramatsumattemattsmattymatzamatzomaubymaudsmaukamaulamaulsmaumsmaumymaundmauntmaurimausymautsmauvemauvymauzymavenmaviemavinmavismawedmawksmawkymawlamawnsmawpsmawrsmaxedmaxesmaximmaxismayanmayasmaybemayedmayormayosmaystmazacmazakmazarmazasmazedmazelmazermazesmazetmazeymazutmbarimbarsmbilambirambretmbubembugameadsmeakemeaksmealsmealymeanemeansmeantmeanymearemeasemeathmeatsmeatymebbemebosmeccamechamechsmecksmecummedalmediamedicmediimedinmedlemeechmeedsmeejameepsmeersmeetsmeffsmeidsmeikomeilsmeinsmeintmeinymeismmeithmekkamelammelasmelbamelchmeldsmeleemelesmelicmelikmellsmeloemelonmelosmeltsmeltymemesmemicmemosmenadmencemendsmenedmenesmengemengsmenilmensamensemenshmentamentomentsmenusmeousmeowsmerchmercsmercymerdemerdsmeredmerelmerermeresmergemerilmerismeritmerksmerlemerlsmerrymersemerskmesadmesalmesasmescameselmesemmesesmeshymesiamesicmesnemesonmessymestomesylmetalmetasmetedmetegmetelmetermetesmethimethomethsmethymeticmetifmetismetolmetremetromettameumsmeusemevedmevesmewedmewlsmeyntmezesmezzamezzemezzomgalsmhorrmiaismiaoumiaowmiasmmiaulmicasmichemichimichtmicksmickymicosmicramicromiddymidgemidgymidismidstmiensmieuxmievemiffsmiffymiftymiggsmightmigmamigodmihasmihismikanmikedmikesmikosmikramikvamilchmildsmilermilesmilfsmiliamilkomilksmilkymillemillsmillymilormilosmilpamiltsmiltymiltzmimedmimeomimermimesmimicmimismimsyminaeminarminasmincemincymindimindsminedminerminesmingemingimingsmingyminimminisminkeminksminnyminorminosminsemintsmintyminusminxymiraamirahmirchmiredmiresmirexmiridmirinmirknmirksmirkymirlsmirlymirosmirrlmirrsmirthmirvsmirzamisalmischmisdomisermisesmisgomiskymislsmisosmissamissymistomistsmistymitasmitchmitermitesmiteymitiemitismitremitrymittamittsmiveymivvymixedmixenmixermixesmixiemixismixtemixupmiyasmizenmizesmizzymmkaymnememoaismoakymoalsmoanamoansmoanymoarsmoatsmobbymobedmobeemobesmobeymobiemoblemobosmocapmochamochimochsmochymocksmockymocosmocusmodalmodelmodemmodermodesmodgemodiimodinmodocmodommodusmoenimoersmofosmogarmogasmoggymogosmogramoguemogulmoharmohelmohosmohrsmohuamohurmoilemoilsmoiramoiremoistmoitsmoitymojosmokermokesmokeymokismokkymokosmokusmolalmolarmolasmoldsmoldymoledmolermolesmoleymoliemollamollemollomollsmollymoloimolosmoltomoltsmoluemolvimolysmomesmomiemommamommemommymomosmompemomusmonadmonalmonasmondemondomonermoneymongomongsmonicmoniemonksmonosmonpemontemonthmontymoobsmoochmoodsmoodymooedmooeymooksmoolamoolimoolsmoolymoongmoonimoonsmoonymoopsmoorsmoorymoosemoothmootsmoovemopedmopermopesmopeymoppymopsymopusmoraemorahmoralmoranmorasmoratmoraymoreemorelmoresmorgymoriamorinmormomornamornemornsmoronmorormorphmorramorromorsemortsmorukmosedmosesmoseymosksmossomossymostemostomostsmotedmotelmotenmotesmotetmoteymothsmothymotifmotismotonmotormottemottomottsmottymotusmotzamouchmouesmoufsmouldmoulemoulsmoultmoulymoundmountmoupsmournmousemoustmousymouthmovedmovermovesmoviemowasmowedmowermowiemowramoxasmoxiemoyasmoylemoylsmozedmozesmozosmpretmradsmsasamtepemuchomucicmucidmucinmuckomucksmuckymucormucromucusmudarmuddymudgemudifmudimmudirmudramuffsmuffymuftimuggamuggsmuggymughomugilmugosmuhlymuidsmuilsmuirsmuirymuistmujikmukimmuktimulaimulchmulctmuledmulesmuleymulgamuliemullamullsmulsemulshmumbomummsmummymumphmumpsmumsymumusmunchmundsmundumungamungemungimungomungsmungymuniamunismunjamunjsmuntsmuntumuonsmuralmurasmuredmuresmurexmurghmurgimuridmurksmurkymurlsmurlymurramurremurrimurrsmurrymurthmurtimurukmurvamusarmuscamusedmuseemusermusesmusetmushamushymusicmusitmusksmuskymusosmussemussymustamusthmustsmustymutasmutchmutedmutermutesmuthamuticmutismutonmuttimuttsmutummuvvamuxedmuxesmuzakmuzzymvulamvulemvulimyallmyalsmylarmynahmynasmyoidmyomamyonsmyopemyopsmyopymyrrhmysidmysiemythimythsmythymyxosmzeesnaamsnaansnaatsnabamnabbynabesnabisnabksnablanabobnachenachonacrenadasnadirnaevenaevinaffsnagarnagasnagesnaggynagornahalnaiadnaibsnaicenaidsnaieonaifsnaiksnailsnailynainsnaiosnairanairunaivenajibnakasnakednakernakfanalasnalednallanamadnamaknamaznamednamernamesnammanamusnanasnancenancynandunannanannynanosnantenantinantonantsnantynanuanapasnapednapesnapohnapoonappanappenappynarasnarconarcsnardsnaresnaricnarisnarksnarkynarodnarranarrenasalnashinashonasisnasonnastynasusnataknatalnatchnatesnatisnattonattynatyanauchnauntnavalnavarnavednavelnavesnavewnavvynawabnawalnazarnazesnazirnazisnazzyndujaneafenealsneantneapsnearsneathneatoneatsnebbynebeknebelnechenecksneddyneebsneedsneedyneefsneeldneeleneembneemsneepsneeseneezenefienegrinegronegusneifsneighneistneivenelianelisnellynemasnemicnemnsnemptnenesnentaneonsneosaneozanepernepitneralneramnerdsnerdynerfsnerkanerksnerolnertsnertznervenervyneskinestsnestynetasnetesnetopnettanettsnettyneuksneumeneumsnevelnevernevesnevisnevusnevvynewbsnewednewelnewernewienewlynewsynewtsnexalnexinnextsnexumnexusngaiongakanganangapingatingegengomangoningramngweenibbynicadnicednicerniceynichenichtnicksnickynicolnidalnidednidesnidornidusnieceniefsniessnievenifesniffsniffynifleniftynigernigganighsnightnigreniguanihilnikabnikahnikaunilasnillsnimbinimbsnimbynimpsninerninesninjaninnyninonnintaninthnioponiozanipasnipetnippyniqabnirlsnirlyniseinisinnissenisusnitalniternitesnitidnitonnitrenitronitrynittanittonittynivalnivasnivelnixednixernixesnixienizamnjirlnkosinmolinmolsnoahsnobbynoblenoblynocksnodalnoddynodednodesnodumnodusnoelsnoemanoemenogalnoggsnoggynohownoiasnoilsnoilynointnoirenoirsnoisenoisynokesnolesnollenollsnolosnomadnomasnomennomesnomicnomoinomosnonannonasnoncenoncynondanondononesnonetnongsnonicnonisnonnanonnononnynonylnoobsnooisnooitnooksnookynoonenoonsnoopsnoosenoovenopalnorianorienorisnorksnormanormsnorthnosednosernosesnoseynoshinosirnotalnotamnotchnotednoternotesnotumnougsnoujanouldnoulenoulsnounsnounynoupsnoustnovaenovasnovelnovianovionovumnowaynowdsnowednowlsnowtsnowtynoxalnoxasnoxesnoyaunoyednoyesnrttanrtyansimanubbynubianuchanucinnuddynudernudesnudgenudgynudienudzhnuevonuffsnugaenujolnukednukesnullanullonullsnullynumbsnumennummynumpsnunksnunkynunnynunusnuquenurdsnurdynurlsnurrsnursenurtsnurtznusednusesnutsonutsynuttynyaffnyalanyamsnyingnylonnymphnyongnyssanyungnyusenyuzeoafosoakedoakenoakeroakumoaredoareroasaloasesoasisoastsoatenoateroathsoavesobangobbosobeahobeliobeseobeysobiasobiedobiitobitsobjetoboesoboleoboliobolsoccamoccuroceanocherochesochreochryockerocoteocreaoctadoctaloctanoctasoctetocticoctlioctyloculiodahsodalsodderoddlyodeonodeumodismodistodiumodoomodorsodourodumsodyleodylsofaysoffaloffedofferoffieoflagoftenofterofuroogamsogeedogeesogginoghamogiveogledogleroglesogmicogresoheloohiasohingohmicohoneoicksoidiaoiledoileroiletoinksointsoiranojimeokapiokaysokehsokiesokingokoleokrasokrugoktasolateoldenolderoldieoldlyolehsoleicoleinolentoleosoleumoleyloligooliosolivaoliveollasollavollerollieologyolonaolpaeolpesomasaomberombreombusomdahomdasomddaomdehomeesomegaomensomersomiaiomitsomlahommelomminomnesomovsomrahomulsonceroncesoncetoncusondesondolonelyonersoneryongononiononiumonkusonlaponlayonmunonnedonsenonsetontalonticooaasoobitoohedooidsoojahoomphoontsoopakoopedoopsyoorieoosesootidooyahoozedoozesoozieoozleopahsopalsopensopepeoperaoperyopgafopihiopineopingopiumopposopsatopsinopsitoptedopteropticopzitorachoracyoralsorangoransorantorateorbatorbedorbicorbitorcasorcinorderordieordosoreadorfesorfulorganorgiaorgicorgueoribiorielorigoorixaorlesorlonorlopormerorneeornisorpedorpinorrisortetorthoorvalorzososarsoscarosetroseysoshacosieroskinoslinosmicosmolosoneossiaostiaotakuotaryotherothylotiumottarotterottosoubitoucheouchtouedsouensoughtouijaoulksoumasounceoundyoupasoupedoupheouphsoureyourieouselousiaoustsoutbyoutdooutedoutenouteroutgooutieoutreoutroouttaouzelouzosovalsovaryovateovelsovensoversovertovineovismovistovoidovoliovoloovuleowareowariowcheowersowiesowingowledowlerowletownedownerownioowresowrieowsenoxbowoxeasoxersoxeyeoxideoxidsoxiesoximeoximsoxineoxlipoxmanoxmenoxteroyamaoyersozekiozenaozoneozziepaahopaalspaanspacaipacaspacaypacedpacerpacespaceypachapackspackypacospactapactspadampadaspaddopaddypadispadlepadmapadoupadrepadripaeanpaedopaeonpaganpagedpagerpagespaglepagnepagodpagripahitpahospahuspaikspailspainspaintpaipepaipspairepairspaisapaisepakaypakkapakkipakuapakulpalakpalarpalaspalaypaleapaledpalerpalespaletpalispalkipallapallspallupallypalmspalmypalpipalpspalsapalsypaluspambypampapanaxpancepanchpandapandspandypanedpanelpanespangapangspanicpanimpanirpankopankspannapannepannipannypansypantopantspantypaolipaolopapadpapalpapaspapawpaperpapespapeypappipappypapriparaeparasparchparcspardipardspardyparedparenpareoparerparespareuparevpargepargoparidparisparkaparkiparksparkyparleparlyparmaparmoparmsparolparpsparraparrsparryparsepartepartipartspartyparveparvopasagpasarpaschpaseopasespashapashmpaskapasmopaspypassepassupastapastepastspastypataspatchpatedpateepatelpatenpaterpatespathspatiapatinpatiopatkapatlypatsypattapattepattupattypatuspauaspaulspausepauxipavanpavaspavedpavenpaverpavespavidpaviepavinpavispavonpavvypawaspawawpawedpawerpawkspawkypawlspawnspaxespayedpayeepayerpayorpaysdpeacepeachpeagepeagspeakepeakspeakypealspeanspearepearlpearspeartpeasepeasypeatspeatypeavypeazepebaspecanpechspeciapeckepeckspeckypectspedalpedespedispedonpedospedropeecepeekspeekypeelspeelypeenspeentpeeoypeepepeepspeepypeerspeerypeevepeevopeggypeghspegmapegospeinepeinspeisepeisypeizepekanpekaupekeapekespekidpekinpekoepelaspelaupelchpelespelfspellspelmapelogpelonpelshpeltapeltspeluspenalpencependspendupenedpenespengopeniepenispenkspennapennepennipennypensepensypentspeolapeonspeonypeplapeplepeponpepospeppypepsipequiperaeperaiperceperchpercsperduperdypereaperesperfsperilperisperksperkyperleperlspermspermypernepernsperogperpsperryperseperspperstpertspervepervopervspervypeschpeskypesospestapestopestspestypetalpetarpeterpetitpetospetrepetripettipettopettypewedpeweepewitpeysepffttphagephangpharepharmphasephasmpheerphemephenepheonphesephialphiesphishphizzphloxphobephocaphonephonophonsphonyphoohphooophotaphotophotsphotyphphtphubsphutsphutuphwatphylaphylephymaphynxphysapiaispianipianopianspibalpicalpicaspiccypiceypichipickspickypiconpicotpicrapiculpiecepiedspiendpierspiertpietapietspietypiezopiggypightpiglypigmypiingpikaspikaupikedpikelpikerpikespikeypikispikulpilaepilafpilaopilarpilaupilawpilchpileapiledpileipilerpilespileypilinpilispillspilonpilotpilowpilumpiluspimaspimpspinaspinaxpincepinchpindapindspinedpinerpinespineypingapingepingopingspinkopinkspinkypinnapinnypinolpinonpinotpintapintopintspinuppionspionypiouspioyepioyspipalpipaspipedpiperpipespipetpipidpipispipitpippypipulpiquepiquipiraipirkspirlspirnspirogpirrepirripirrspiscopisespiskypisospissypistepitaspitchpithspithypitonpitotpitsopitsupittapittupiumapiumspivospivotpixelpixespixiepiyutpizedpizerpizespizzaplaasplaceplackplagaplageplaidplaigplainplaitplancplaneplanhplankplansplantplapsplashplasmplastplateplatsplattplatyplaudplaurplavsplayaplaysplazapleadpleaspleatplebeplebspleckpleeppleinplenapleneplenopleonpleshpletsplewsplexiplicapliedplierpliespligsplimsplingplinkplipsplishploatploceplockplodsploitplombplongplonkplookplootplopsploreplotsplotzploukploutplowsplowtployeployspluckpludspluespluffplugsplukeplumbplumeplumpplumsplumyplungplunkpluotplupsplushpluteplutoplutyplyerpneuspoachpoakapoakepoalopobbypoboypocanpochepochopockspockypodalpoddypodexpodgepodgypodiapodospoduspoemspoenapoepspoesypoetepoetspogeypoggepoggypogospoguepohedpoilupoindpointpoirepoisepokalpokedpokerpokespokeypokiepokitpolarpoledpolerpolespoleypoliopolispoljepolkapolkspollopollspollypolospoltspolyppolyspomaspombepomespommepommypomospompapompsponceponcypondspondyponesponeypongapongopongspongyponksponorpontopontspontyponzupooaypoochpoodspooedpooeypoofspoofypoohspoohypoojapookapookspoolspoolypoonspoopapoopspoopypooripoortpootspootypoovepoovypopespopiapopospoppapoppypopsypopupporaeporalporchporedporerporesporeyporgeporgyporinporksporkypornopornspornyportaporteporthportsportyporusposcaposedposerposesposetposeyposhopositposolpossepostepostspotaepotaipotchpotedpotespotinpotoopotropotsypottopottspottypoucepouchpouffpoufspoufypouispoukepoukspoulepoulppoultpoundpoupepouptpourspousypoutspoutypovospowanpowerpowiepowinpowispowltpowndpownspownypowrepowsypoxedpoxespoyaspoyntpoyoupoysepozzypraampradspragsprahupramspranaprangprankpraosprapsprasepratepratsprattpratyprausprawnprayspreakpredypreedpreempreenpreespreifprekepremspremyprentpreonpreopprepspresapresepressprestpretapreuxpreveprexypreysprialprianpriceprickpricypridepridypriedpriefprierpriesprigsprillprimaprimeprimiprimoprimpprimsprimypringprinkprintprionpriorpriseprismprisspriusprivyprizeproalproasprobeprobsprobyproddprodsproemprofsprogsproinprokeproleprollpromopromsproneprongpronkproofprookprootpropsproraproreproseprosoprossprostprosyprotoproudproulproveprowkprowlprowsproxyproynprudepruneprunopruntprunyprutapryanpryerprysepsalmpseudpshawpshutpsiaspsionpsoaepsoaipsoaspsorapsychpsyopptishptypepubbypubcopubespubicpubispubsypucanpucerpucespuckapuckspuddypudgepudgypudicpudorpudsypuduspuerspuffapuffspuffypuggypugilpuhaspujahpujaspukaspukedpukerpukespukeypukkapukuspulaopulaspuledpulerpulespulikpulispulkapulkspullipullspullypulmopulpspulpypulsepuluspulutpumaspumiepumpspumpypunaspuncepunchpungapungipungopungspungypunimpunjipunkapunkspunkypunnypuntopuntspuntypupaepupalpupaspupilpuppapuppypupuspuraopuraupurdapurdypuredpureepurerpurespurgapurgepurinpurispurlspurospurpspurpypurrepurrspurrypursepursypurtypusespushypuslepussyputasputerputidputinputonputosputtiputtoputtsputtuputtyputzapuukopuyaspuzelpuztapwnedpyatspyetspygalpygmypyinspylonpynedpynespyoidpyotspyralpyranpyrespyrexpyricpyrospyruspyuffpyxedpyxespyxiepyxispzazzqadisqaidsqajaqqanatqapikqiblaqilasqipaoqophsqormaquabsquackquadsquaffquagsquailquairquaisquakequakyqualequalmqualyquankquantquarequarkquarlquartquashquasiquassquatequatsquawkquawsquaydquaysqubitqueanqueckqueekqueemqueenqueerquellquemequenaquernqueryquesoquestquetequeuequeynqueysqueyuquibsquichquickquidsquiesquietquiffquilaquillquiltquimsquinaquinequinkquinoquinsquintquipoquipsquipuquirequirkquirlquirtquistquitequitsquoadquodsquoifquoinquoisquoitquollquonkquopsquorkquorlquotaquotequothquoukquoysquranqurshquyteraadsraakerabatrabbirabicrabidrabisracedracerracesracheracksraconradarraddiraddyradgeradgyradifradiiradioradixradonrafeeraffsraffyrafikrafiqraftsraftyragasragderagedrageeragerragesraggaraggsraggyragisragusrahedrahuiraiahraiasraidsraikeraiksrailerailsrainerainsrainyrairdraiseraitaraithraitsrajahrajasrajesrakedrakeerakerrakesrakhirakiarakisrakkiraksirakusralesrallirallyralphramalrameeramenramesrametramieraminramisrammyramonrampsramseramshramusranasranceranchrandorandsrandyranedraneeranesrangarangerangirangsrangyranidranisrankeranksrannsrannyranserantsrantyrapedrapeeraperrapesrapherapidrapinrapperapsoraredrareerarerraresrarksrasamrasasrasedraserrasesraspsraspyrasserastaratalratanratasratchratedratelraterratesratharatherathsratioratooratosrattirattyratusrauliraunsrauporavedravelravenraverravesraveyravinrawdyrawerrawinrawksrawlyrawnsraxedraxesrayahrayasrayedrayleraylsraynerayonrazairazedrazeerazerrazesrazetrazoorazorreachreactreaddreadsreadyreaisreaksrealmrealorealsreamereamsreamyreansreapsreardrearmrearsreastreatareatereaverebabrebarrebberebecrebelrebidrebitreboprebudrebusrebutrebuyrecalrecapreccereccoreccyreceprecitrecksreconrectarecterectirectorecuerecurrecutredanreddsreddyrededredesrediaredidredifredigredipredlyredonredosredoxredryredubredugreduxredyereeafreechreedereedsreedyreefsreefyreeksreekyreelsreelyreemsreensreerdreestreevereezerefanrefedrefelreferrefforefisrefitrefixreflyrefryregalregarregesregetregexreggoregiaregieregleregmaregnaregosregotregurrehabrehemreifsreifyreignreikireiksreinereingreinkreinsreirdreistreiverejasrejigrejonrekedrekesrekeyrelaxrelayreletrelicrelierelitrellorelosremanremapremenremetremexremitremixremourenalrenayrendsrendurenewreneyrengarengsrenigreninrenksrennerenosrenterentsreoilreorgrepasrepatrepayrepegrepelrepenrepinreplareplyreposrepotreppsreprorepunreputreranrerigrerunresamresatresawresayreseeresesresetresewresidresinresitresodresolresowrestorestsrestyresueresusretagretamretaxretchretemretiaretieretinretipretoxretroretryreunereupsreuserevelrevetrevierevowrevuerewanrewaxrewedrewetrewinrewonrewthrexesrezesrhabdrheasrheidrhemerheumrhiesrhimerhinerhinorhodyrhombrhonerhumbrhymerhymyrhynerhytariadsrialsriantriatariatoribasribbyribesricedricerricesriceyricherichtricinricksriderridesridgeridgyridicrielsriemsrieveriferriffsriffyriflerifteriftsriftyriggsrightrigidrigmorigolrigorrikkarikwariledrilesrileyrillerillsrillyrimaerimedrimerrimesrimonrimusrincerindsrindyrinesringeringsringyrinksrinseriojarioneriotsriotyripedripenriperripesrippsriqqsrisenriserrisesrishirisksriskyrispsristsrisusritesritherittsritzyrivalrivasrivedrivelrivenriverrivesrivetriyalrizasroachroadsroadyroakeroakyroamsroansroanyroarsroaryroastroaterobborobedroberrobesrobinroblerobotrobugroburrocherocksrockyrodedrodeorodesrodnyroersroganrogerrogueroguyrohanrohesrohunrohusroidsroilsroilyroinsroistrojakrojisrokedrokerrokesrokeyrokosrolagroleorolesrolfsrollsrollyromalromanromeoromerrompsrompurompyronderondoroneoronesroninronneronterontsronukroodsroofsroofyrooksrookyroomsroomyroonsroopsroopyroosarooseroostrootsrootyropedroperropesropeyroqueroralroresroricroridrorierortsrortyrosalroscorosedrosesrosetrosharoshirosinrositrospsrossarossorostirostsrotalrotanrotasrotchrotedrotesrotisrotlsrotonrotorrotosrottarotterottorottyrouenrouesrouetroufsrougeroughrougyrouksroukyrouleroulsroumsroundroupsroupyrouseroustrouterouthroutsrovedrovenroverrovesrowanrowdyrowedrowelrowenrowerrowetrowierowmerowndrownsrowthrowtsroyalroyetroyneroystrozesrozetrozitruachruanarubairubanrubbyrubelrubesrubinrubiorublerubliruborrubusrucheruchyrucksrudasruddsruddyruderrudesrudierudisruedaruersrufferuffsruffyrufusrugaerugalrugasrugbyruggyruiceruingruinsrukhsruledrulerrulesrullyrumalrumbarumborumenrumesrumlyrummyrumorrumporumpsrumpyruncerunchrundsrunedrunerrunesrungsrunicrunnyrunosruntsruntyrunupruoterupeerupiaruralrurpsrurusrusasrusesrushyrusksruskyrusmarusserustsrustyruthsrutinruttyruvidryalsrybatryijiryijyrykedrykesrymerrymmeryndsryotiryotsryperrypinrytheryugisaagssabalsabedsabersabessabhasabinsabirsabjisablesabossabotsabrasabresabzisackssacrasacresaddosaddysadessadhesadhusadicsadissadlysadossadzasaetasafedsafersafessagarsagassagersagessaggysagossagumsahabsahebsahibsaicesaicksaicssaidssaigasailssaimssainesainssaintsairssaistsaithsajousakaisakersakessakiasakissaktisaladsalalsalassalatsalepsalessaletsalicsalissalixsallesallysalmisalolsalonsalopsalpasalpssalsasalsesaltosaltssaltysaludsaluesalutsalvesalvosamansamassambasambosameksamelsamensamessameysamfisamfusammysampisampssanadsandssandysanedsanersanessangasanghsangosangssankosansasantosantssaolasapansapidsaporsappysaransardssaredsareesargesargosarinsarirsarissarkssarkysarodsarossarussarvosasersasinsassesassysataisataysatedsatemsatersatessatinsatissatyrsaubasaucesauchsaucysaughsaulssaultsaunasaunfsauntsaurysautesautssauvesavedsaversavessaveysavinsavorsavoysavvysawahsawedsawersaxessayassayedsayeesayersayidsaynesayonsaystsazesscabsscadsscaffscagsscailscalascaldscalescallscalpscalyscampscamsscandscansscantscapascapescapiscarescarfscarpscarsscartscaryscathscatsscattscaudscaupscaurscawssceatscenascendscenescentschavschifschmoschulschwascifiscindscionsciresclimscobescodyscoffscogsscoldsconescoogscoopscootscopascopescopsscorescornscorpscotescotsscougscoupscourscoutscowlscowpscowsscrabscraescragscramscranscrapscratscrawscrayscreescrewscrimscripscrobscrodscrogscrooscrowscrubscrumscubascudiscudoscudsscuffscuftscugssculkscullsculpsculsscumsscupsscurfscursscusescutascutescutsscuzzscyessdaynsdeinsealsseameseamsseamyseanssearesearsseaseseatsseazesebumseccosechssectssedansedersedessedgesedgysedumseedsseedyseeksseeldseelsseelyseemsseepsseepyseerssefersegarsegassegnisegnosegolsegosseguesehriseifsseilsseineseirsseiseseismseityseizaseizesekossektsselahselesselfsselfyselkysellasellesellsselvasemassemeesemensemessemiesemissenassendssenessenexsengisennasenorsensasensesensisensusentesentisentssenvysenzasepadsepalsepiasepicsepoysepposeptaseptsseracseraiseralseredsererseresserfssergeseriasericserifserinserirserksseronserowserraserreserrsserryserumserveservoseseysessasetaesetalsetersethssetonsettssetupsevaksevenseversevirsewansewarsewedsewelsewensewersewinsexedsexersexessexorsextosextsseyensezesshackshadeshadsshadyshaftshagsshahsshakashakeshakoshaktshakyshaleshallshalmshaltshalyshamashameshamsshandshankshansshapeshapsshardsharesharksharnsharpshartshashshaulshaveshawlshawmshawnshawsshayashaysshchisheafshealshearsheasshedssheelsheensheepsheersheetsheikshelfshellshendshengshentsheolsherdsheresheroshetsshevashewnshewsshiaishiedshielshiershiesshiftshillshilyshimsshineshinsshinyshiokshipsshireshirkshirrshirsshirtshishshisoshistshiteshitsshiurshivashiveshivsshlepshlubshmekshmoeshoalshoatshockshoedshoershoesshogishogsshojishojosholashoneshonkshookshoolshoonshoosshootshopeshopsshoreshorlshornshortshoteshotsshottshoudshoutshoveshowdshownshowsshowyshoyushredshrewshrisshrowshrubshrugshtarshtikshtumshtupshubashuckshuleshulnshulsshunsshuntshurashushshuteshutsshwasshyershylysialssibbssibiasibylsicessichtsickosickssickysidassidedsidersidessideysidhasidhesidlesiegesieldsienssientsiethsieursievesiftssighssightsigilsiglasigmasignasignssigrisijossikassikersikessildssiledsilensilersilessilexsilkssilkysillssillysilossiltssiltysilvasimarsimassimbasimissimpssimulsincesindssinedsinessinewsingesingssinhssinkssinkysinsisinussipedsipessippysiredsireesirensiressirihsirissirocsirrasirupsisalsisessissysistasistssitarsitchsitedsitessithesitkasitupsitussiversixersixessixmosixtesixthsixtysizarsizedsizelsizersizesskagsskailskaldskankskarnskartskateskatsskattskawsskeanskearskedsskeedskeefskeenskeerskeesskeetskeevskeezskeggskegsskeinskelfskellskelmskelpskeneskensskeosskepsskermskerssketsskewsskidsskiedskierskiesskieyskiffskillskimoskimpskimsskinkskinsskintskiosskipsskirlskirrskirtskiteskitsskiveskivysklimskoalskobeskodyskoffskofsskogsskolsskoolskortskoshskranskrikskrooskuasskugsskulkskullskunkskyedskyerskyeyskyfsskyreskyrsskyteslabsslacksladeslaesslagsslaidslainslakeslamsslaneslangslankslantslapsslartslashslateslatsslatyslaveslawsslaysslebssledssleeksleepsleersleetsleptslewssleyssliceslickslideslierslilyslimeslimsslimyslingslinkslipeslipssliptslishslitsslivesloanslobssloesslogssloidslojdslokaslomosloomsloopslootslopeslopsslopyslormsloshslothslotssloveslowssloydslubbslubssluedsluessluffslugssluitslumpslumsslungslunkslurbslurpslurssluseslushslutsslyerslylyslypesmaaksmacksmaiksmallsmalmsmaltsmarmsmartsmashsmazesmearsmeeksmeessmeiksmekesmellsmeltsmerksmewssmicksmilesmilysmirksmirrsmirssmitesmithsmitssmizesmocksmogssmokesmokosmokysmoltsmoorsmootsmoresmorgsmotesmoutsmowtsmugssmurssmushsmutssnabssnacksnafusnagssnailsnakesnakysnapssnaresnarfsnarksnarlsnarssnarysnashsnathsnawssneadsneaksneapsnebssnecksnedssneedsneersneessnellsnibssnicksnidesniedsniessniffsniftsnigssnipesnipssnipysnirtsnitssnivesnobssnodssnoeksnoepsnogssnokesnoodsnooksnoolsnoopsnootsnoresnortsnotssnoutsnowksnowssnowysnubssnucksnuffsnugssnushsnyessoakssoapssoapysoaresoarssoavesobassobersocassocessociasockosockssoclesodassoddysodicsodomsofarsofassoftasoftssoftysogersoggysohursoilssoilysojassojussokahsokensokessokolsolahsolansolarsolassoldesoldisoldosoldssoledsoleisolersolessolidsolonsolossolumsolussolvesomansomassonarsoncesondesonessongosongssongysonicsonlysonnesonnysonsesonsysooeysookssookysoolesoolssoomssoopssootesoothsootssootysophssophysoporsoppysoprasoralsorassorbisorbosorbssordasordosordssoredsoreesorelsorersoressorexsorgosornssorrasorrysortasortssorussothssotolsottosoucesouctsoughsoukssoulssoulysoumssoundsoupssoupysourssousesouthsoutssowarsowcesowedsowersowffsowfssowlesowlssowmssowndsownesowpssowsesowthsoxessoyassoylesoyuzsozinspacespackspacyspadespadospadsspaedspaerspaesspagsspahispailspainspaitspakespaldspalespallspaltspamsspanespangspankspansspardsparesparksparsspartspasmspatespatsspaulspawlspawnspawsspaydspaysspazaspazzspeakspealspeanspearspeatspeckspecsspectspeedspeelspeerspeilspeirspeksspeldspelkspellspeltspendspentspeosspermspeshspetsspeugspewsspewyspialspicaspicespickspicsspicyspidespiedspielspierspiesspiffspifsspikespiksspikyspilespillspiltspimsspinaspinespinkspinsspinyspirespirtspiryspitespitsspitzspivssplatsplaysplitsplogspodespodsspoilspokespoofspookspoolspoomspoonspoorspootsporesporksportsposasposhsposospotsspoutspradspragspratsprayspredspreesprewsprigspritsprodsprogspruesprugspudsspuedspuerspuesspugsspulespumespumyspunkspurnspursspurtsputaspyalspyresquabsquadsquatsquawsqueesquegsquibsquidsquitsquizsrslystabsstackstadestaffstagestagsstagystaidstaigstainstairstakestalestalkstallstampstandstanestangstankstansstaphstapsstarestarkstarnstarrstarsstartstarystashstatestatsstatustaunstavestawsstayssteadsteakstealsteamsteanstearsteddstedestedssteedsteeksteelsteemsteensteepsteersteezsteiksteilsteinstelastelestellstemestemsstendstenostensstentstepssteptsteresternstetsstewsstewysteysstichstickstiedstiesstiffstilbstilestillstiltstimestimsstimystingstinkstintstipastipestirestirkstirpstirsstivestivystoaestoaistoasstoatstobsstockstoepstogsstogystoicstoitstokestolestolnstomastompstondstonestongstonkstonnstonystoodstookstoolstoopstoorstopestopsstoptstorestorkstormstorystossstotsstottstounstoupstourstoutstovestownstowpstowsstradstraestragstrakstrapstrawstraystrepstrewstriastrigstrimstripstropstrowstroystrumstrutstubsstuckstucsstudestudsstudystuffstullstulmstummstumpstumsstungstunkstunsstuntstupastupesturesturtstushstyedstyesstylestylistylostymestymystyrestytesuavesubahsubaksubassubbysubersubhasuccisuckssuckysucresudansuddssudorsudsysuedesuentsuerssuetesuetssuetysugansugarsughssugossuhursuidssuingsuintsuitesuitssujeesukhssukissukuksulcisulfasulfosulkssulkysullssullysulphsulussumacsumissummasumossumphsumpssunissunkssunnasunnssunnysuntssunupsuonasupedsupersupessuprasurahsuralsurassuratsurdssuredsurersuressurfssurfysurgesurgysurlysurrasusedsusessushisusussutorsutrasuttaswabsswackswadsswageswagsswailswainswaleswalyswamiswampswamyswangswankswansswapsswaptswardswareswarfswarmswartswashswathswatsswaylswaysswealswearsweatswedesweedsweelsweepsweersweessweetsweirswellsweltsweptswerfsweysswiesswiftswigsswileswillswimsswineswingswinkswipeswireswirlswishswissswithswitsswiveswizzswobsswoleswollswolnswoonswoopswopsswoptswordsworeswornswotsswounswungsybbesybilsyboesybowsyceesycessyconsyedssyenssykersykessylissylphsylvasymarsynchsyncssyndssynedsynessynodsynthsypedsypessyphssyrahsyrensyrupsysopsythesyvertaalstaatatabactabbytabertabestabidtabistablatabletablstabootabortabostabuntabustacantacestacettachetachitachotachstacittackstackytacostactstadahtaelstaffytafiataggytagmataguatahastahrstaigataigstaikotailstainstainttairataishtaitstajestakastakentakertakestakhitakhttakintakistakkytalaktalaqtalartalastalcstalcytaleatalertalestaliktalkstalkytallstallytalmatalontalpataluktalustamaltamastamedtamertamestamintamistammytampstanastangatangitangotangstangytanhstaniatankatankstankytannatansutansytantetantitantotantytapastapedtapentapertapestapettapirtapistappatapustarastardotardstardytaredtarestargatargetarkatarnstaroctaroktarostarottarpstarretarrytarsetarsitartetartstartytarzytasartascatasedtasertasestaskstassatassetassotastetastotastytatartatertatestathstatietatoutattstattytatustaubetauldtaunttauontaupetautstautytavahtavastavertawaftawaitawastawedtawertawietawnytawsetawtstaxedtaxertaxestaxistaxoltaxontaxortaxustayratazzatazzeteachteadeteadsteaedteakstealsteamstearstearyteaseteatsteazetechstechytectatecumteddyteelsteemsteendteeneteensteenyteersteethteetsteffsteggsteguategusteheetehrsteiidteilsteindteinstekketelaetelcotelestelexteliatelictellstellyteloitelostemedtemestempitempotempstempttemsetenchtendstendutenestenettengeteniatennetennotennytenontenortensetenthtentstentytenuetepaltepastepeetepidtepoyteraiterasterceterekteresterfeterfstergatermsterneternsterraterreterrytersetertsterzateslatestatesteteststestytetestethstetratetriteuchteughtewedteweltewittexastexestextatextsthackthagithaimthalethalithanathanethangthankthansthanxtharmtharsthawsthawtthawythebethecatheedtheektheestheftthegntheictheintheirthelfthemathemethenstheortheowtherethermthesethespthetathetethewsthewythickthiefthighthigsthilkthillthinethingthinkthinsthiolthirdthirlthofttholetholithongthornthorothorpthosethotsthousthowlthraethrawthreethrewthridthripthrobthroethrowthrumthudsthugsthujathumbthumpthunkthurlthuyathymethymithymytianstiaratiaretiarstibiaticalticcaticedticestichytickstickytidaltiddytidedtidestiefstierstiffstifostiftstigertigestighttigontikastikestikiatikistikkatilaktildetiledtilertilestillstillytilthtiltstimbotimedtimertimestimidtimontimpstinastincttindstineatinedtinestingetingstinkstinnytintotintstintytipistippytipsytipuptiredtirestirlstirostirrstirthtitantitartitastitchtitertithetithititintitirtitistitletitretittytituptiyintiynstizestizzytoadstoadytoasttoazetockstockytocostodaytoddetoddytodeatodostoeastoffstoffytoftstofustogaetogastogedtogestoguetohostoidytoiletoilstoingtoisetoitstoitytokaytokedtokentokertokestokostolantolartolastoledtolestollstollytoltstolustolyltomantombotombstomentomestomiatomintommetommytomostomoztonaltonditondotonedtonertonestoneytongatongstonictonkatonkstonnetonustoolstoomstoonstoothtootstopaztopedtopeetopektopertopestophetophitophstopictopistopoitopostoppytoquetorahtorantorastorchtorcstorestorictoriitorostorottorrstorsetorsitorsktorsotortatortetortstorustosastosedtosestoshytossytosyltotaltotedtotemtotertotestottytouchtoughtoukstounstourstousetousytoutstouzetouzytowaitowedtoweltowertowietownotownstownytowsetowsytowtstowzetowzytoxictoxintoyedtoyertoyontoyostozedtozestozietrabstracetracktracttradetradstradytragatragitragstragutraiktrailtraintraittramptramstranktranqtranstranttrapetrapotrapstrapttrashtrasstratstratttravetrawltrayftraystreadtreattrecktreedtreentreestrefatreiftrekstrematremstrendtresstresttretstrewstreyftreystriactriadtrialtribetricetricktridetriedtriertriestrifatrifftrigotrigstriketrildtrilltrimstrinetrinstrioltriortriostripetripstripytristtritetroadtroaktroattrocktrodetrodstrogstroistroketrolltromptronatronctronetronktronstrooptrooztropetropotrothtrotstrouttrovetrowstroystrucetrucktruedtruertruestrugotrugstrulltrulytrumptrunktrusstrusttruthtryertryketrymatrypstrysttsadetsaditsarstskedtsubatsubotuanstuarttuathtubaetubaltubartubastubbytubedtubertubestuckstufastuffetuffstuftstuftytugratuiletuinatuismtuktutulestuliptulletulpatulpstulsitumidtummytumortumpstumpytunastundstunedtunertunestungstunictunnytupektupiktupletuqueturboturdsturfsturfyturksturmeturmsturnsturntturonturpsturrstushytuskstuskytuteetutestutortuttituttytutustuxestuyertwaestwaintwalstwangtwanktwatstwaystweaktweedtweeltweentweeptweertweettwerktwerptwicetwiertwigstwilltwilttwinetwinktwinstwinytwiretwirktwirltwirptwisttwitetwitstwixttwocstwoertwonktwyertyeestyerstyingtyiyntykestylertympstyndetynedtynestypaltypedtypestypeytypictypostyppstyptotyrantyredtyrestyrostythetzarsubacsubityudalsudderudonsudyogugaliuggeduhlanuhuruukaseulamaulansulcerulemaulminulmosulnadulnaeulnarulnasulpanultraulvasulyieulzieumamiumbelumberumbleumbosumbraumbreumiacumiakumiaqummahummasummedumpedumphsumpieumptyumrahumrasunagiunaisunaptunarmunaryunausunbagunbanunbarunbedunbidunboxuncapuncesunciauncleuncosuncoyuncusuncutundamundeeunderundidundosundueundugunethunfedunfitunfixungagungetungodungotungumunhatunhipunicaunifyunionuniosuniteunitsunityunjamunkedunketunkeyunkidunkutunlapunlawunlayunledunlegunletunlidunlitunmadunmanunmetunmewunmixunodeunoldunownunpayunpegunpenunpinunplyunpotunputunredunridunrigunripunsawunsayunseeunsetunsewunsexunsodunsubuntaguntaxuntieuntiluntinunwedunwetunwitunwonunzipupbowupbyeupdosupdryupendupfulupjetuplayupleduplituppedupperupranuprunupseeupsetupseyuptakupteruptieuraeiuraliuraosurareurariuraseurateurbanurbexurbiaurdeeurealureasuredoureicureidurenaurenturgedurgerurgesurialurineuriteurmanurnalurnedurpedursaeursidursonurubuurupaurvasusageusensusersusetausherusingusneausnicusqueustadusterusualusureusurpusuryuteriuteroutileutteruvealuveasuvulavacasvacayvacuavacuivacuovadasvadedvadesvadgevagalvaguevagusvaidsvailsvairevairsvairyvajravakasvakilvalesvaletvalidvalisvallivalorvalsevaluevalvevampsvampyvandavanedvanesvangavangsvantsvapedvapervapesvapidvaporvaranvarasvardavardovardyvarecvaresvariavarixvarnavarusvarvevasalvasesvastsvastyvatasvathavaticvatjevatosvatusvauchvaultvauntvautevautsvawtevaxesvealevealsvealyveenaveepsveersveeryveganvegasvegesveggovegievegosvehmeveilsveilyveinsveinyvelarveldsveldtvelesvellsvelumvenaevenalvenasvendsvenduveneyvengeveninvenomventiventsvenuevenusverbaverbsverdevergeverraverreverryversaverseversoverstvertevertsvertuvervevespavestavestsvetchveuvevevesvexedvexervexesvexilvezirvialsviandvibedvibesvibexvibeyvicarvicedvicesvichyvicusvideoviersvieuxviewsviewyvifdaviffsvigasvigiavigilvigorvildevilervillavillevillivillsvimenvinalvinasvincavinedvinervinesvinewvinhovinicvinnyvinosvintsvinylviolavioldviolsviperviralviredvireoviresvirgavirgevirgoviridvirlsvirtuvirusvisasvisedvisesvisievisitvisnavisnevisonvisorvistavistovitaevitalvitasvitexvitrovittavivasvivatvivdavivervivesvividvivosvivrevixenvizirvizorvlastvleisvliesvlogsvoarsvoblavocabvocalvocesvoddyvodkavodouvodunvoemavogievoguevoicevoicivoidsvoilavoilevoipsvolaevolarvoledvolesvoletvolkevolksvoltavoltevoltivoltsvolvavolvevomervomitvotedvotervotesvouchvougevouluvowedvowelvowervoxelvoxesvozhdvraicvrilsvroomvrousvrouwvrowsvuggsvuggyvughsvughyvulgovulnsvulvavuttyvygievyingwaacswackewackowackswackywadaswaddswaddywadedwaderwadeswadgewadiswadtswaferwaffswaftswagedwagerwageswaggawagonwagyuwahaywaheywahoowaidewaifswaiftwailswainswairswaistwaitewaitswaivewakaswakedwakenwakerwakeswakfswaldowaldswaledwalerwaleswaliewaliswalkswallawallswallywaltywaltzwamedwameswamuswandswanedwaneswaneywangswankswankywanlewanlywannawantawantswantywanzewaqfswarbswarbywardswaredwareswarezwarkswarmswarnswarpswarrewarstwartswartywaseswashiwashywasmswaspswaspywastewastswatapwatchwaterwattswauffwaughwaukswaulkwaulswaurswavedwaverwaveswaveywawaswaweswawlswaxedwaxenwaxerwaxeswayedwazirwazoowealdwealsweambweanswearswearyweavewebbyweberwechtwedelwedgewedgyweedsweedyweeisweekeweeksweelsweemsweensweenyweepsweepyweestweeteweetswefteweftsweidsweighweilsweirdweirsweiseweizewekaswelchweldswelkewelkswelktwellswellywelshweltswembswenchwendswengewennywentswerfsweroswershwestswetaswetlywexedwexeswhackwhalewhamowhamswhangwhapswharewharfwhatawhatswhaupwhaurwhealwhearwheatwheekwheelwheenwheepwheftwhelkwhelmwhelpwhenswherewhetswhewswheyswhichwhidswhieswhiffwhiftwhigswhilewhilkwhimswhinewhinswhinywhioswhipswhiptwhirlwhirrwhirswhishwhiskwhisswhistwhitewhitswhitywhizzwholewhompwhoofwhoopwhootwhopswhorewhorlwhortwhosewhosowhowswhumpwhupswhydawiccawickswickywiddywidenwiderwideswidowwidthwieldwielswifedwifeswifeywifiewiftswiftywiganwiggawiggywightwikiswilcowildswiledwileswilgawiliswiljawillswillywiltswimpswimpywincewinchwindswindywinedwineswineywingewingswingywinkswinkywinnawinnswinoswinzewipedwiperwipeswiredwirerwireswirrawirriwisedwiserwiseswishawishtwispswispywistswitanwitchwitedwiteswithewithswithywittywivedwiverwiveswizenwizeswizzowoadswoadywoaldwockswodgewodgywofulwojuswokenwokerwokkawoldswolfswollywolvewomanwomaswombswombywomenwomynwongawongiwonkswonkywontswoodswoodywooedwooerwoofswoofywooldwoolswoolywoonswoopswoopywoosewooshwootzwoozywordswordyworksworkyworldwormswormyworryworseworstworthwortswouldwoundwovenwowedwoweewowsewoxenwrackwrangwrapswraptwrastwratewrathwrawlwreakwreckwrenswrestwrickwriedwrierwrieswringwristwritewritswrokewrongwrootwrotewrothwrungwryerwrylywuddywuduswuffswullswungawurstwuseswushuwussywuxiawyledwyleswyndswynnswytedwyteswythexebecxeniaxenicxenonxericxeroxxerusxoanaxolosxraysxviiixylanxylemxylicxylolxylylxystixystsyaarsyaassyabasyabbayabbyyaccayachtyackayacksyaddayaffsyageryagesyagisyagnayahooyairdyajnayakkayakowyalesyamenyampayampyyamunyandyyangsyanksyapokyaponyappsyappyyarakyarcoyardsyareryarfayarksyarnsyarrayarrsyartayartoyatesyatrayaudsyauldyaupsyawedyaweyyawlsyawnsyawnyyawpsyayasyboreycladycledycondydradydredyeadsyeahsyealmyeansyeardyearnyearsyeastyecchyechsyechyyedesyeedsyeeekyeeshyeggsyelksyellsyelmsyelpsyeltsyentayenteyerbayerdsyerksyesesyesksyestsyestyyetisyettsyeuchyeuksyeukyyevenyevesyewenyexedyexesyfereyieldyikedyikesyillsyinceyipesyippyyirdsyirksyirrsyirthyitesyitieylemsylideylidsylikeylkesymoltympesyobboyobbyyocksyodelyodhsyodleyogasyogeeyoghsyogicyoginyogisyohahyohayyoickyojanyokanyokedyokegyokelyokeryokesyokulyolksyolkyyolpsyomimyompsyonicyonisyonksyonnyyoofsyoopsyoposyoppoyoresyorgayorksyorpsyouksyoungyournyoursyourtyouseyouthyowedyowesyowieyowlsyowsayowzayoyosyraptyrentyrivdyrnehysameytostyuansyucasyuccayucchyuckoyucksyuckyyuftsyugasyukedyukesyukkyyukosyulanyulesyummoyummyyumpsyuponyuppyyurtayurtsyuzuszabrazackszaidazaidezaidyzairezakatzamaczamakzamanzambozamiazamiszanjazantezanzazanzezappyzardazarfszariszatiszawnszaxeszaydezayinzazenzealszebeczebrazebubzebuszedaszeerazeinszendozerdazerkszeroszestszestyzetaszexeszezeszhomozhushzhuzhzibetziffsziganzikrszilaszilchzillazillszimbizimbszincozincszincyzinebzineszingszingyzinkezinkyzinoszippozippyziramzitiszittyzizelzizitzlotezlotyzoaeazoboszobuszoccozoeaezoealzoeaszoismzoistzokorzollezombizonaezonalzondazonedzonerzoneszonkszooeazooeyzooidzookszoomszoomyzoonszootyzoppazoppozorilzoriszorrozorsezoukszoweezowiezuluszupanzupaszuppazurfszuzimzygalzygonzymeszymic"
  log_str_1 db "guess "
  log_str_2 db " eliminates "
  log_str_3 db " words on average", 0xA
  ; literal 36 + 1 ending byte + 5 letters from guess = 42

  prompt db "Enter guess and result (lares __g_y): "
  prompt_len equ $ - prompt
  
  press_enter db "Press enter to continue...", 0xA
  press_enter_len equ $ - press_enter

section .bss
  ; each word is 8 bytes (left 3 are 0, right 5 are u8 letters)
  ; 14855 words * 8 = 118840 bytes
  words_encoded resb 118840 ; dictionary

  possible_secrets resb 118840 ; dictionary, but is changed as we eliminate words

  ; each bitmap needs to store 26*11 bits via 3 XMM registers. (16*3 = 48 bytes)
  ; there are 14855 bitmaps. 14855*48 = 713040
  alignb 16 ; yay! this works. now ptest doesnt give an exception.
  cached_bitmaps: resb 713040