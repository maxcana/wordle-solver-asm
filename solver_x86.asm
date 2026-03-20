;---------------------
;  NASM Assembler file
;---------------------
default rel

section .text
  global _start ; linux api
  global main ; windows api

; windows api stuff
  extern GetStdHandle
  extern WriteFile
  extern ExitProcess


; bitmap testing!
debug:
  pxor xmm0, xmm0
  pxor xmm1, xmm1
  pxor xmm2, xmm2

  mov rbx, 128
  mov rcx, 285
  call write_raw_bit_sequence_revised

  call safe_print_bitmap

  hlt
main:
_start:
  ; Set up arguments for print function
  mov rdi, msg_size
  lea rsi, [rel msg] ; lea rsi, [rel msg] is same as mov rsi, msg. but encoded differently, 
  ; since you put in the DIFFERENCE (maybe only one byte) instead of the MEMORY (8 bytes) as the operand and use a different opcode (lea vs mov).
  ; the instruction still returns the same memory address, it just calculates it at runtime.
  ; must use [rel msg] not [abs msg] or else compiler instantly complains and doesn't compile
  ; solver_x86.obj:solver_x86.asm:(.text+0x1e): relocation truncated to fit: IMAGE_REL_AMD64_ADDR32 against `.data'
  call win64_print

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
  sub rsp, 16
  mov [rsp], r12 ; [rsp] is counter for outermost loop
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
      mov [rsp], ebx
      mov [rsp+8], ebx
      mov [rsp+16], ebx
      mov [rsp+24], ebx

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
  
          call write_raw_bit

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
          dec r11b
          test edx,edx
          je no_max
          
          has_max:
          mov bl, byte [rsp+rcx] ; bl = min
          cmp r11b, dl
          jne write_bit ; only write if count != min
          je continue
          
          no_max:
          mov bl, byte [rsp+rcx] ; bl = min
          cmp r11b, bl
          jae continue ; only write if count < min
          
          write_bit:
            movzx rcx, al ; fix rcx, make it ltr again
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

      cmp esi, 0x8180404 ; aiyee
      jne no_debug
      xchg rdi,rsi
      call safe_print_word ; print rdi - guess
      xchg rdi,rsi
      call safe_print_word ; print rsi - secret
      call safe_print_bitmap
      hlt
      no_debug:

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
    
    call win64_print

    mov rsp, r15 ; revive old rsp

    inc qword [rsp]
    cmp qword [rsp], 14855
    jne for_PG
  
  add rsp, 16
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

  call win64_print

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
  call win64_print
  add rsp, 16


; rdi - File descriptor (1 for stdout)
; rsi - Pointer to the string to print
; rdx - Length of the string
; Return: None
print:
  push rbp
  mov rbp, rsp
  mov rax, 1
  syscall
  pop rbp
  ret

; rdi - Exit code
; Return: None
exit:
  push rbp
  mov rbp, rsp
  mov rax, 60
  syscall
  pop rbp
  ret

; rsi - Pointer to the string to print
; rdi - Length of the string
; modifies: rcx, rdx, rax, r8, r9
; saves: xmm0, xmm1, xmm2
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

jmp_table:
  dq gray
  dq yellow
  dq green
  
section .data
  msg db "Hello, world!", 0xA
  msg_size equ $ - msg
  words db "aahedaaliiaapasaarghaartiabacaabaciabackabacsabaftabahtabakaabampabandabaseabashabaskabateabayaabbasabbedabbesabbeyabbotabceeabeamabearabeatabeerabeleabengabersabetsabeysabhorabideabiesabiusabjadabjudabledablerablesabletablowabmhoabnetabodeabohmaboilabomaaboonabordaboreabornabortaboutaboveabramabrayabrimabrinabrisabseyabsitabunaabuneaburaaburnabuseabutsabuzzabyesabysmabyssacaisacaraacariaccasacchaaccoyaccraacedyaceneacerbacersacetaacharachedacherachesacheyachooacidsacidyaciesacingaciniackeeackeracmesacmicacnedacnesacockacoelacoldaconeacornacralacredacresacridacronacrosacrylactasactedactinactonactoractusacuteacylsadageadaptadatsadawnadawsadaysadbotaddasaddaxaddedadderaddinaddioaddleaddraadeadadeemadeptadhanadhocadieuadiosaditsadlibadmanadmenadminadmitadmixadnexadobeadoboadoonadoptadorbadoreadornadownadozeadradadrawadredadretadripadsumadukiadultaduncadustadvewadvtsadytaadytsadzedadzesaeciaaedesaegeraegisaeonsaerieaerosaesiraevumafaldafancafaraafarsafearaffixafflyafionafireafizzaflajaflapaflowafoamafootaforeafoulafretafritafrosafteraftosagainagalsagamaagamiagamyagapeagarsagaspagastagateagatyagaveagazeagbasageneagentagersaggagaggeraggieaggriaggroaggryaghasagidiagilaagileagingagiosagismagistagitaagleeagletagleyaglooaglowaglusagmasagogeagogoagoneagonsagonyagoodagoraagreeagriaagrinagrosagrumaguedaguesagueyagunaagushagutiaheadaheapahentahighahindahingahintaholdaholeahullahuruaidasaidedaideraidesaidoiaidosaieryaigasaightailedaimagaimakaimedaimeraineeaingaaioliairedairerairnsairthairtsaisleaitchaitusaiveraixesaiyahaiyeeaiyohaiyooaizleajiesajivaajugaajupaajwanakaraakeesakelaakeneakingakitaakkasakkerakoiaakojaakoyaaksedaksesalaapalackalalaalamoalandalanealangalansalantalapaalapsalarmalaryalataalatealaysalbasalbeealbidalbumalceaalcesalcidalcosaldeaalderaldolaleakaleckalecsaleemalefsaleftalephalertalewsaleyealfasalgaealgalalgasalgidalginalgoralgosalgumaliasalibialickalienalifsalignalikealimsalinealiosalistalivealiyaalkiealkinalkosalkydalkylallanallayalleeallelallenalleralleyallinallisallodallotallowalloyallusallylalmahalmasalmehalmesalmudalmugalodsaloedaloesaloftalohaaloinalonealongaloofaloosalosealoudalowealphaaltaralteralthoaltosalulaalumsalumyalurealurkalvaralwayamahsamainamariamaroamassamateamautamazeambanamberambitambleambosambryamebaameeramendameneamensamentamiasamiceamiciamideamidoamidsamiesamigaamigoamineaminoaminsamirsamissamityamlasammanammasammonammosamniaamnicamnioamoksamoleamongamoreamortamouramoveamowtampedampleamplyampulamritamuckamuseamylsananaanataanchoancleanconandicandroanearaneleanentangasangelangerangleangloangryangstanighanileanilsanimaanimeanimianionaniseankerankhsankleankusanlasannalannanannasannatannexannoyannulannumannusanoasanodeanoleanomyansaeansasantaeantarantasantedantesanticantisantraantreantsyanuraanvilanyonaortaapaceapageapaidapartapaydapaysapeakapeekapersapertaperyapgaraphidaphisapianapingapiolapishapismapneaapodeapodsapolsapoopaportappalappamappayappelappleapplyapproapptsappuiappuyapresapronapsesapsisapsosaptedapteraptlyaquaeaquasarabaaraksarameararsarbaharbasarborarcedarchiarcosarcusardebardorardriareadareaearealarearareasarecaareddaredearefyareicarenaarenearepaarerearetearetsarettargalarganargilargleargolargonargotargueargusarhatariasarielarikiarilsariotarisearisharitharkedarledarlesarmedarmerarmetarmilarmorarnasarnisarnutarobaarohaaroidaromaarosearpasarpenarraharrasarrayarretarrisarrowarrozarsedarsesarseyarsisarsonartalartelarterarticartisartlyartsyaruhearumsarvalarveearvosarylsasadaasanaasconascotascusasdicashedashenashesashetasideasityaskaraskedaskeraskewaskoiaskosaspenasperaspicaspieaspisasproassaiassamassayassedassesassetassezassotasterastirastunasuraaswayaswimasylaatapsataxyatigiatiltatimyatlasatmanatmasatmosatocsatokeatoksatollatomsatomyatoneatonyatopyatriaatripattapattarattasatteratticatuasauchtaudadaudaxaudioauditaugenaugeraugesaughtauguraulasaulicauloiaulosaumilaunesauntsauntyauraeauralauraraurasaureiauresauricaurisaurumautosauxinavailavaleavantavastavelsavensaversavertavgasavianavineavionaviseavisoavizeavoidavowsavyzeawaitawakeawardawareawariawarnawashawatoawaveawaysawdlsaweelawetoawfulawingawkinawmryawnedawnerawokeawolsaworkaxelsaxialaxileaxilsaxingaxiomaxionaxiteaxledaxlesaxmanaxmenaxoidaxoneaxonsayahsayayaayelpaygreayinsaymagayontayresayrieazansazideazidoazineazlonazoicazoleazonsazoteazothazukiazureazurnazuryazygyazymeazymsbaaedbaalsbaapsbabasbabbybabelbabesbabkababoobabulbabusbaccabaccobaccybachabachsbacksbackybacnebaconbadambaddybadgebadlybaelsbaffsbaffybaftabaftsbagelbaggybaghsbagiebagsybaguabahtsbahusbahutbaiksbailebailsbairnbaisabaithbaitsbaizabaizebajanbajrabajribajusbakedbakenbakerbakesbakrabalasbaldsbaldybaledbalerbalesbalksbalkyballoballsballybalmsbalmybaloibalonbaloobalotbalsabaltibalunbalusbalutbamasbambibammabammybanakbanalbancobancsbandabandhbandsbandybanedbanesbangsbaniabanjobanksbankybannsbantsbantubantybantzbanyabaonsbaozibappubapusbarbebarbsbarbybarcabardebardobardsbardybaredbarerbaresbarfibarfsbarfybargebaricbarksbarkybarmsbarmybarnsbarnybaronbarpsbarrabarrebarrobarrybaryebasalbasanbasasbasedbasenbaserbasesbashabashobasicbasijbasilbasinbasisbasksbasonbassebassibassobassybastabastebastibastobastsbatchbatedbatesbathebathsbatikbatonbatosbattabattsbattubattybaudsbauksbaulkbaursbavinbawdsbawdybawksbawlsbawnsbawrsbawtybayasbayedbayerbayesbaylebayoubaytsbazarbazasbazoobballbdaysbeachbeadsbeadybeaksbeakybealsbeamsbeamybeanobeansbeanybeardbearebearsbeastbeathbeatsbeatybeausbeautbeauxbebopbecapbeckebecksbedadbedelbedesbedewbedimbedyebeechbeedibeefsbeefybeepsbeersbeerybeetsbefitbefogbegadbeganbegarbegatbegembegetbeginbegobbegotbegumbegunbeigebeigybeingbeinsbeirabeisabekahbelahbelarbelaybelchbeleebelgabeliebelitbellebellibellobellsbellybelonbelowbeltsbelvebemadbemasbemixbemudbenchbendsbendybenesbenetbengabenisbenjibennebennibennybentobentsbentybepatberayberesberetbergsberkoberksbermebermsberobberryberthberylbesatbesawbeseebesesbesetbesitbesombesotbestibestsbetasbetedbetelbetesbethsbetidbetonbettabettybevanbevelbeverbevorbevuebevvybewdybewetbewigbezelbezesbezilbezzybhaisbhajibhangbhatsbhavabhelsbhootbhunabhutsbiachbialibialybibbsbibesbibisbiblebiccybicepbicesbickybiddybidedbiderbidesbidetbidisbidonbidribieldbiersbiffobiffsbiffybifidbigaebiggsbiggybighabightbiglybigosbigotbihonbijoubikedbikerbikesbikiebikkybilalbilatbilbobilbybiledbilesbilgebilgybilksbillsbillybimahbimasbimbobinalbindibindsbinerbinesbingebingobingsbingybinitbinksbinkybintsbiogsbiomebionsbiontbiosebiotabipedbipodbippybirchbirdobirdsbirisbirksbirlebirlsbirosbirrsbirsebirsybirthbirzebirzzbisesbisksbisombisonbitchbiterbitesbiteybitosbitoubitsybittebittsbittybiviabivvybizesbizzobizzyblabsblackbladebladsbladyblaerblaesblaffblagsblahsblainblameblamsblancblandblankblareblartblaseblashblastblateblatsblattblaudblawnblawsblaysblazebleahbleakblearbleatblebsblechbleedbleepbleesblendblentblertblessblestbletsbleysblimpblimyblindblingbliniblinkblinsblinyblipsblissblistbliteblitsblitzblivebloatblobsblockblocsblogsblokeblondblonxbloodblookbloombloopbloreblotsblownblowsblowyblubsbludebludsbludybluedbluerbluesbluetblueybluffbluidblumeblunkbluntblurbblursblurtblushblypeboabsboaksboardboarsboartboastboatsboatybobacbobakbobasbobbybobolbobosboccabocceboccibochebocksbodedbodesbodgebodgybodhibodlebodohboepsboersboetiboetsboeufboffoboffsboganbogeyboggybogiebogleboguebogusboheabohosboilsboingboinkboitebokedbokehbokesbokosbolarbolasboldoboldsbolesboletbolixbolksbollsbolosboltsbolusbomasbombebombobombsbomohbomorboncebondsbonedbonerbonesboneybongobongsboniebonksbonnebonnybonumbonusbonzabonzebooaibooayboobsboobyboodybooedboofyboogyboohsbooksbookyboolsboomsboomyboongboonsboordboorsbooseboostboothbootsbootyboozeboozyboppyborakboralborasboraxbordebordsboredboreeborekborelborerboresborgoboricborksbormsbornaborneboronbortsbortybortzboseybosiebosksboskybosombosonbossabossybosunbotasbotchbotehbotelbotesbotewbothybotosbottebottsbottybougeboughbouksbouleboultboundbounsbourdbourgbournbousebousyboutsboutubovidbowatbowedbowelbowerbowesbowetbowiebowlsbownebowrsbowseboxedboxenboxerboxesboxlaboxtyboyarboyauboyedboyeyboyfsboygsboylaboylyboyosboysybozosbraaibracebrachbrackbractbradsbraesbragsbrahsbraidbrailbrainbrakebraksbrakybramebrandbranebrankbransbrantbrashbrassbrastbratsbravabravebravibravobrawlbrawnbrawsbraxybraysbrazabrazebreadbreakbreambredebredsbreedbreembreerbreesbreidbreisbremebrensbrentbrerebrersbrevebrewsbreysbriarbribebrickbridebriefbrierbriesbrigsbrikibriksbrillbrimsbrinebringbrinkbrinsbrinybriosbrisebriskbrissbrithbritsbrittbrizebroadbrochbrockbrodsbroghbrogsbroilbrokebromebromobroncbrondbroodbrookbroolbroombroosbrosebrosybrothbrownbrowsbruckbrughbruhsbruinbruitbrujabrujobrulebrumebrungbruntbrushbruskbrustbrutebrutsbruvsbuatsbuazebubalbubasbubbabubbebubbybubusbuchubuckobucksbuckubudasbuddybudedbudesbudgebudisbudosbuenabuffabuffebuffibuffobuffsbuffybufosbuftybuganbuggybuglebuhlsbuhrsbuiksbuildbuiltbuistbukesbukosbulbsbulgebulgybulksbulkybullabullsbullybulsebumbobumfsbumphbumpsbumpybunasbuncebunchbuncobundebundhbundsbundtbundubundybungsbungybuniabunjebunjybunkobunksbunnsbunnybuntsbuntybunyabuoysbuppyburanburasburbsburdsburetburfiburghburgsburinburkaburkeburksburlsburlyburnsburntburooburpsburqaburraburroburrsburrybursaburseburstbusbybusedbusesbushybusksbuskybussubustibustsbustybutchbuteobutesbutlebutohbuttebuttsbuttybututbutylbuxombuyerbuyinbuzzybwanabwazibydedbydesbykedbykesbylawbyresbyrlsbyssibytesbywaycaaedcabalcabascabbycabercabincablecabobcaboccabrecacaocacascachecackscackycacticaddycadeecadescadetcadgecadgycadiecadiscadrecaecacaesecafescaffecaffscagedcagercagescageycagotcahowcaidscainscairdcairncajoncajuncakedcakescakeycalfscalidcalifcalixcalkscallacallecallscalmscalmycaloscalpacalpscalvecalyxcamancamascamelcameocamescamiscamoscampicampocampscampycamuscanalcandocandycanedcanehcanercanescangscanidcannacannscannycanoecanoncansocanstcanticantocantscantycapascapaxcapedcapercapescapexcaphscapizcaplecaponcaposcapotcapricapulcaputcarapcaratcarbocarbscarbycardicardscardycaredcarercarescaretcarexcargocarkscarlecarlscarnecarnscarnycarobcarolcaromcaroncarpecarpicarpscarrscarrycarsecartacartecartscarvecarvycasascascocasedcasercasescaskscaskycastecastscasuscatchcatercatescattycaudacaukscauldcaulkcaulscaumscaupscauricausacausecavascavedcavelcavercavescaviecavilcavuscawedcawkscaxonceaseceazecebidcecalcecumcedarcededcedercedescedisceibaceiliceilscelebcellacellicellocellscellycelomceltscensecentocentscentuceorlcepescerciceredcerescergeceriacericcernecerocceroscertscertycessecestacesticetescetylcezvechaapchaatchacechackchacochadochadschafechaffchaftchainchairchaischalkchalschampchamschanachangchankchantchaoschapechapschaptcharachardcharecharkcharmcharrcharschartcharychasechasmchatschavachavechavschawkchawlchawschayachayscheapcheatchebacheckchedicheebcheekcheepcheercheetchefschekachelachelpchemochemscherechertchesschestchethchevychewschewychiaochiaschibachibschicachichchickchicochicschidechiefchielchikochikschildchilechilichillchimbchimechimochimpchinachinechingchinkchinochinschipschirkchirlchirmchirochirpchirrchirtchiruchitichitschivachivechivschivychizzchockchocochocschodechogschoilchoirchokechokochokycholacholicholochompchonschoofchookchoomchoonchopschordchorechosechosschotachottchoutchouxchowkchowschubschuckchufachuffchugschumpchumschunkchurlchurnchurrchusechutechutschylechymechyndcibolcidedcidercidescielscigarciggyciliacillscimarcimexcinchcinctcinescinqscionscippicircacircscirescirlscirriciscocissycistscitalcitedciteecitercitescivescivetcivicciviecivilcivvyclachclackcladecladsclaesclagsclaimclairclameclampclamsclangclankclansclapsclaptclaroclartclaryclashclaspclassclastclatsclautclaveclaviclawsclayscleanclearcleatcleckcleekcleepclefscleftclegscleikclemsclepecleptclerkcleveclewsclickcliedcliescliffcliftclimbclimeclineclingclinkclintclipeclipscliptclitscloakcloamclockclodscloffclogsclokeclombclompcloneclonkclonscloopclootclopsclosecloteclothclotscloudclourclouscloutcloveclownclowscloyecloysclozeclubscluckcluedcluesclueyclumpclungclunkclypecnidacoachcoactcoadycoalacoalscoalycoaptcoarbcoastcoatecoaticoatscobbscobbycobiacoblecobotcobracobzacocascoccicoccocockscockycocoacocoscocuscodascodeccodedcodencodercodescodexcodoncoedscoffscogiecogoncoguecohabcohencohoecohogcohoscoifscoigncoilscoinscoirscoitscokedcokescokeycolascolbycoldscoledcolescoleycoliccolincollecollscollycologcoloncolorcoltscolzacomaecomalcomascombecombicombocombscombycomercomescometcomfycomiccomixcommacommecommocommscommycompocompscomptcomtecomusconchcondoconedconesconexconeyconfscongacongecongoconiaconicconinconksconkyconneconnscontecontoconusconvocoochcooedcooeecooercooeycoofscookscookycoolscoolycoombcoomscoomycoonscoopscooptcoostcootscootycoozecopalcopaycopedcopencopercopescophacoppycopracopsecopsycoquicoralcoramcorbecorbycordacordscoredcorercorescoreycorgicoriacorkscorkycormscornicornocornscornucornycorpscorsecorsocoseccosedcosescosetcoseycosiecostacostecostscotancotchcotedcotescothscottacottscouchcoudecoughcouldcountcoupecoupscourbcourdcourecourscourtcoutacouthcovedcovencovercovescovetcoveycovincowalcowancowedcowercowkscowlscowpscowrycoxaecoxalcoxedcoxescoxibcoyaucoyedcoyercoylycoypucozedcozencozescozeycoziecraalcrabscrackcraftcragscraiccraigcrakecramecrampcramscranecrankcranscrapecrapscrapycrarecrashcrasscratecravecrawlcrawscrayscrazecrazycreakcreamcredocredscreedcreekcreelcreepcreescreincremacremecremscrenacrepecrepscreptcrepycresscrestcrewecrewscriascribocribscrickcriedcriercriescrimecrimpcrimscrinecrinkcrinscrioscripecripscrisecrispcrisscrithcritscroakcrocicrockcrocscroftcrogscrombcromecronecronkcronscronycrookcroolcrooncropscrorecrosscrostcroupcroutcrowdcrowlcrowncrowscrozecruckcrudecrudocrudscrudycruelcruescruetcruftcrumbcrumpcrunkcruorcruracrusecrushcrustcrusycruvecrwthcryercrynecryptctenecubbycubebcubedcubercubescubiccubitcuckscuddacuddycuecacuffocuffscuifscuingcuishcuitscukesculchculetculexcullscullyculmsculpaculticultscultycumeccumincundycuneicunitcunnycuntscupelcupidcuppacuppycuprocuratcurbscurchcurdscurdycuredcurercurescuretcurfscuriacuriecuriocurlicurlscurlycurnscurnycurrscurrycursecursicurstcurvecurvycuseccushycuskscuspscuspycussocusumcutchcutercutescuteycutiecutincutiscuttocuttycutupcuveecuzescwtchcyanocyanscybercycadcycascyclecyclocydercylixcymaecymarcymascymescymolcyniccystscytescytonczarsdaalsdabbadacesdachadacksdadahdadasdaddydadisdadladadosdaffsdaffydaggadaggydagosdahisdahlsdaikodailydainedaintdairydaisydakerdaleddalekdalesdalisdalledallydaltsdamandamardamesdammedamnadamnsdampsdampydancedancydandadandydangsdaniodanksdannydansedantsdappydarafdarbsdarcydareddarerdaresdargadargsdaricdarisdarksdarkydarlsdarnsdarredartsdarzidashidashydataldateddaterdatesdatildatosdattodatumdaubedaubsdaubydaudsdaultdauntdaursdautsdavendavitdawahdawdsdaweddawendawgsdawksdawnsdawtsdayaldayandaychdayntdazeddazerdazesdbagsdeadsdeairdealsdealtdeansdearedearndearsdearydeashdeathdeavedeawsdeawydebagdebardebbydebeldebesdebitdebtsdebuddebugdeburdebusdebutdebyedecaddecafdecaldecandecaydecimdeckodecksdecordecosdecoydecrydecyldedaldeedsdeedydeelydeemsdeensdeepsdeeredeersdeetsdeevedeevsdefatdeferdeffodefisdefogdegasdegumdegusdeicedeidsdeifydeigndeilsdeinkdeismdeistdeitydekeddekesdekkodelaydeleddelesdelfsdelftdelisdelladellsdellydelosdelphdeltadeltsdelvedemandemesdemicdemitdemobdemoidemondemosdemotdemptdemurdenardenaydenchdenesdenetdenimdenisdensedentedentsdeochdeoxydepotdepthderatderayderbyderedderesderigdermadermsdernsdernyderosderpyderroderryderthdervsdesexdeshidesisdesksdessedetagdeterdetoxdeucedevasdeveldevildevisdevondevosdevotdewandewardewaxdeweddexesdexiedexysdhabadhaksdhalsdhikrdhobidholedholldholsdhonidhotidhowsdhutidiactdialsdianadianediarydiazodibbsdiceddicerdicesdiceydichtdicksdickydicotdictadictodictsdictudictydiddydidiedidisdidosdidstdiebsdielsdienedietsdiffsdightdigitdikasdikeddikerdikesdikeydildodillidillsdillydimbodimerdimesdimlydimpsdinardineddinerdinesdingedingodingsdingydinicdinksdinkydinlodinnadinosdintsdiochdiodediolsdiotadippydipsodiramdirerdirgedirkedirksdirlsdirtsdirtydisasdiscidiscodiscsdishydisksdismeditalditasditchditedditesditsydittodittsdittyditzydivandivasdiveddiverdivesdiveydivisdivnadivosdivotdivvydiwandixiedixitdiyasdizendizzydjinndjinsdoabsdoatsdobbydobesdobiedobladobledobradobrodochtdocksdocosdocusdoddydodgedodgydodosdoeksdoersdoestdoethdoffsdogaldogandogesdogeydoggodoggydogiedoglydogmadohyodoiltdoilydoingdoitsdojosdolcedolcidoleddoleedolesdoleydoliadoliedollsdollydolmadolordolosdoltsdomaldomeddomesdomicdonahdonasdoneedonerdongadongsdonkodonnadonnedonnydonordonsydonutdoobsdoocedoodydoofsdooksdookydooledoolsdoolydoomsdoomydoonadoorndoorsdoozydopasdopeddoperdopesdopeydoppedoraddorbadorbsdoreedoresdoricdorisdorjedorksdorkydormsdormydorpsdorrsdorsadorsedortsdortydosaidosasdoseddosehdoserdosesdoshadotaldoteddoterdotesdottydouardoubtdoucedoucsdoughdouksdouladoumadoumsdoupsdouradousedoutsdoveddovendoverdovesdoviedowakdowardowdsdowdydoweddoweldowerdowfsdowiedowledowlsdowlydownadownsdownydowpsdowrydowsedowtsdoxeddoxesdoxiedoyendoylydozeddozendozerdozesdrabsdrackdracodraffdraftdragsdraildraindrakedramadramsdrankdrantdrapedrapsdrapydratsdravedrawldrawndrawsdraysdreaddreamdreardreckdreeddreerdreesdregsdreksdrentdreredressdrestdreysdribsdricedrieddrierdriesdriftdrilldrilydrinkdripsdriptdrivedrockdroiddroildroitdrokedroledrolldromedronedronydroobdroogdrookdrooldroopdropsdroptdrossdroukdrovedrowndrowsdrubsdrugsdruiddrumsdrunkdrupedrusedrusydruxydryaddryasdryerdrylydsobodsomoduadsdualsduansduarsdubbodubbyducalducatducesduchyducksduckyductiductsduddydudeddudesduelsduetsduettduffsdufusduingduitsdukasdukeddukesdukkadukundulcedulesduliadullsdullydulsedumasdumbodumbsdumkadumkydummydumpsdumpydunamduncedunchdunesdungsdungydunksdunnodunnydunshduntsduomiduomodupedduperdupesdupleduplyduppyduraldurasduredduresdurgydurnsdurocdurosduroydurradurrsdurrydurstdurumdurzidusksduskydustsdustydutchduvetduxesdwaaldwaledwalmdwamsdwamydwangdwarfdwaumdweebdwelldweltdwiledwinedyadsdyersdyingdykeddykesdykeydykondyneldynesdynosdzhoseagereagleeaglyeagreealedealeseanedeardsearedearlsearlyearnsearntearsteartheasedeaseleasereaseseasleeastseateneatereatheeatineavedeavereavesebankebbedebbetebenaebeneebikeebonsebonyebookecadsecardecashechedechesechosecigseclatecoleecrusedemaedgededgeredgesedictedifyedileeditseduceeducteejiteensyeerieeeveneevereevnseffedefferefitsegadsegersegesteggareggedeggeregmasegretehingeidereidoseighteigneeikedeikoneildseironeiselejectejidoekdamekingekkaselainelandelanselateelbowelchieldereldinelecteleetelegyelemielfedelfineliadelideelinteliteelmenelogeelogyeloinelopeelopselpeeelsineludeeluteelvanelvenelverelvesemacsemailembarembayembedemberembogembowemboxembusemceeemeeremendemergemeryemeusemicsemirsemitsemmasemmeremmetemmewemmysemojiemongemoteemoveemptsemptyemuleemureemydeemydsenactenarmenateendedenderendewendowendueenemaenemyenewsenfixeniacenjoyenlitenmewennogennuienokienolsenormenowsenrolensewenskyensueenterentiaentreentryenureenurnenvoienvoyenzymeolideorlseosinepactepeesepenaepeneephahephasephodephorepicsepochepodeepoptepoxyeppieeprisequalequesequidequiperaseerbiaerecterevsergonergosergoterhusericaerickericseringernederneserodeeroseerrederrorerseseructerugoerupteruvservenervilescarescotesileeskareskeresnesesrogessayessesesterestocestopestroetageetapeetatsetensethaletherethicethneethosethyleticsetnasetrogettinettleetudeetuisetweeetymaeughseukedeupadeuroseusolevadeevegsevenseventeverteveryevetsevhoeevictevilseviteevoheevokeewersewestewhowewkedexactexaltexamsexcelexeatexecsexeemexemeexertexfilexierexiesexileexineexingexistexiteexitsexodeexomeexonsexpatexpelexposextolextraexudeexulsexultexurbeyasseyerseyingeyotseyraseyreseyrieeyrirezinefabbofabbyfablefacedfacerfacesfacetfaceyfaciafaciefactafactofactsfactyfaddyfadedfaderfadesfadgefadosfaenafaeryfaffsfaffyfaggyfaginfagotfaiksfailsfainefainsfaintfairefairsfairyfaithfakedfakerfakesfakeyfakiefakirfalajfalesfallsfalsefalsyfamedfamesfanalfancyfandsfanesfangafangofangsfanksfannyfanonfanosfanumfaqirfaradfarcefarcifarcyfardsfaredfarerfaresfarlefarlsfarmsfarosfarrofarsefartsfascifastifastsfatalfatedfatesfatlyfatsofattyfatwafauchfaughfauldfaultfaunafaunsfaurdfautefautsfauvefavasfavelfaverfavesfavorfavusfawnsfawnyfaxedfaxesfayedfayerfaynefayrefazedfazesfealsfeardfearefearsfeartfeasefeastfeatsfeazefecalfecesfechtfecitfecksfedaifedexfeebsfeedsfeelsfeelyfeensfeersfeesefeezefehmefeignfeintfeistfelchfelidfelixfellafellsfellyfelonfeltsfeltyfemalfemesfemicfemmefemmyfemurfencefendsfendyfenisfenksfennyfentsfeodsfeoffferalfererferesferiaferlyfermifermsfernsfernyferoxferryfessefestafestsfestyfetalfetasfetchfetedfetesfetidfetorfettafettsfetusfetwafeuarfeudsfeuedfeverfewerfeyedfeyerfeylyfezesfezzyfiarsfiatsfiberfibrefibroficesfichefichuficinficosfictaficusfidesfidgefidosfidusfiefsfieldfiendfientfierefierifiersfieryfiestfifedfiferfifesfifisfifthfiftyfiggyfightfigosfikedfikesfilarfilchfiledfilerfilesfiletfiliifilksfillefillofillsfillyfilmifilmsfilmyfilonfilosfilthfilumfinalfincafinchfindsfinedfinerfinesfinisfinksfinnyfinosfiordfiqhsfiquefiredfirerfiresfiriefirksfirmafirmsfirnifirnsfirryfirstfirthfiscsfishofishyfisksfistsfistyfitchfitlyfitnafittefittsfiverfivesfixedfixerfixesfixiefixitfizzyfjeldfjordflabsflackflaffflagsflailflairflakeflaksflakyflameflammflamsflamyflaneflankflansflapsflareflaryflashflaskflatsflavaflawnflawsflawyflaxyflaysfleamfleasfleckfleekfleerfleesfleetflegsflemefleshfleurflewsflexiflexofleysflickflicsfliedflierfliesflimpflimsflingflintflipsflirsflirtfliskfliteflitsflittfloatflobsflockflocsfloesflogsflongfloodfloorflopsflorafloreflorsfloryfloshflossflotafloteflourfloutflownflowsflowyflubsfluedfluesflueyflufffluidflukeflukyflumeflumpflungflunkfluorflurrflushfluteflutyfluytflybyflyerflyinflypeflytefnarrfoalsfoamsfoamyfocalfocusfoehnfogeyfoggyfogiefoglefogosfogoufohnsfoidsfoilsfoinsfoistfoldsfoleyfoliafolicfoliefoliofolksfolkyfollyfomesfondafondsfondufonesfoniofonlyfontsfoodsfoodyfoolsfootsfootyforamforayforbsforbyforcefordofordsforelforesforexforgeforgoforksforkyformaformeformsforteforthfortsfortyforumforzaforzefossafossefouatfoudsfouerfouetfoulefoulsfoundfountfoursfouthfoveafowlsfowthfoxedfoxesfoxiefoyerfoylefoynefrabsfrackfractfragsfrailfraimfraisframefrancfrankfrapefrapsfrassfratefratifratsfraudfrausfraysfreakfreedfreerfreesfreetfreitfremdfrenafreonfrerefreshfretsfriarfribsfriedfrierfriesfrigsfrillfrisefriskfristfritafritefrithfritsfrittfritzfrizefrizzfrockfroesfrogsfrommfrondfronsfrontfroomfrorefrornfroryfroshfrostfrothfrownfrowsfrowyfroyofrozefrugsfruitfrumpfrushfrustfryerfubarfubbyfubsyfucksfucusfuddyfudgefudgyfuelsfuerofuffsfuffyfugalfuggyfugiefugiofugisfuglefuglyfuguefugusfujisfullafullsfullyfulthfulwafumedfumerfumesfumetfundafundifundofundsfundyfungifungofungsfunicfunisfunksfunkyfunnyfunsyfuntsfuralfuranfurcafurlsfurolfurorfurosfurrsfurryfurthfurzefurzyfusedfuseefuselfusesfusilfusksfussyfustsfustyfutonfuzedfuzeefuzesfuzilfuzzyfycesfykedfykesfylesfyrdsfyttegabbagabbygablegaddigadesgadgegadgygadidgadisgadjegadjogadsogaffegaffsgagedgagergagesgaidsgailygainsgairsgaitagaitsgaittgajosgalahgalasgalaxgaleagaledgalesgaliagalisgallsgallygalopgalutgalvogamasgamaygambagambegambogambsgamedgamergamesgameygamicgamingammagammegammygampsgamutganchgandyganefganevgangsganjaganksganofgantsgaolsgapedgapergapesgaposgappygaramgarbagarbegarbogarbsgardagardegaresgarisgarmsgarnigarregarrigarthgarumgasesgashygaspsgaspygassygastsgatchgatedgatergatesgathsgatorgauchgaucygaudsgaudygaugegaujegaultgaumsgaumygauntgaupsgaursgaussgauzegauzygavelgavotgawcygawdsgawksgawkygawpsgawsygayalgayergaylygazalgazargazedgazergazesgazongazoogealsgeansgearegearsgeasageatsgeburgeckogecksgeeksgeekygeepsgeesegeestgeistgeitsgeldsgeleegelidgellygeltsgemelgemmagemmygemotgenaegenalgenasgenesgenetgenicgeniegeniigeningeniogenipgennygenoagenomgenregenrogentsgentygenuagenusgeodegeoidgerahgerbegeresgerlegermsgermygernegessegessogestegestsgetasgetupgeumsgeyangeyerghastghatsghautghazigheesghestghostghoulghuslghyllgiantgibedgibelgibergibesgibligibusgiddygiftsgigasgighegigotgiguegilasgildsgiletgiliagillsgillygilpygiltsgimelgimmegimpsgimpyginchgingagingegingsginksginnyginzogipongippogippygipsygirdsgirlfgirlsgirlygirnsgirongirosgirrsgirshgirthgirtsgismogismsgistsgitchgitesgiustgivedgivengivergivesgizmoglacegladegladsgladyglaikglairglampglamsglandglansglareglaryglassglattglaumglaurglazeglazygleamgleanglebaglebeglebygledegledsgleedgleekgleesgleetgleisglensglentgleysglialgliasglibsglidegliffgliftglikeglimeglimsglintgliskglitsglitzgloamgloatglobeglobiglobsglobyglodegloggglomsgloomgloopglopsgloryglossglostgloutgloveglowsglowyglozegluedgluergluesglueygluggglugsglumeglumsgluongluteglutsglyphgnapignarlgnarrgnarsgnashgnatsgnawngnawsgnomegnowsgoadsgoafsgoaftgoalsgoarygoatsgoatygoavegobangobargobbegobbigobbogobbygobisgobosgodetgodlygodsogoelsgoersgoestgoethgoetygofergoffsgoggagogosgoiergoinggojisgokesgoldsgoldygolemgolesgolfsgollygolpegolpsgombogomergompagonadgonchgonefgonergongsgoniagonifgonksgonnagonofgonysgonzogoobygoodogoodsgoodygooeygoofsgoofygoogsgooksgookygooldgoolsgoolygoomygoonsgoonygoopsgoopygoorsgoorygoosegoosygopakgopikgoralgorasgoraygorbsgordogoredgoresgorgegorisgormsgormygorpsgorsegorsygoshtgossegotchgothsgothygottagouchgougegouksgouragourdgoutsgoutygovedgovesgowangowdsgowfsgowksgowlsgownsgoxesgoyimgoylegraalgrabsgracegradegradsgraffgraftgrailgraingraipgramagramegrampgramsgranagrandgranogransgrantgrapegraphgrapygraspgrassgratagrategratsgravegravsgravygraysgrazegreatgrebegrebogrecegreedgreekgreengreesgreetgregegregogreingrensgrepsgresegrevegrewsgreysgricegridegridsgriefgriffgriftgrigsgrikegrillgrimegrimygrindgrinsgriotgripegripsgriptgripygrisegristgrisygrithgritsgrizegroangroatgrodygrogsgroingroksgromagromsgronegroofgroomgropegrossgroszgrotsgroufgroupgroutgrovegrovygrowlgrowngrowsgrrlsgrrrlgrubsgruedgruelgruesgrufegruffgrumegrumpgrundgruntgrycegrydegrykegrypegryptguacoguanaguanoguansguardguarsguavagubbagucksguckygudesguessguestguffsgugasgugglguideguidoguidsguildguileguiltguimpguiroguisegulabgulaggulargulasgulchgulesguletgulfsgulfygullsgullygulphgulpsgulpygumbogummagummigummygumpsgunasgundigundygungegungygunksgunkygunnyguppyguqingurdygurgegurksgurlsgurlygurnsgurrygurshgurusgushyguslaguslegusligussygustogustsgustygutsyguttaguttyguyedguyleguyotguysegwinegyalsgyansgybedgybesgyeldgympsgynaegyniegynnygynosgyozagypesgyposgyppogyppygypsygyralgyredgyresgyrongyrosgyrusgytesgyvedgyvergyveshaafshaarshaatshabithablehabushacekhackshackyhadalhadedhadeshadjihadsthaemshaerehaetshaffshafizhaftahaftshaggshahamhahashaickhaikahaikshaikuhailshailyhainshainthairshairyhaithhajeshajishajjihakamhakashakeahakeshakimhakushalalhaldihaledhalerhaleshalfahalfshalidhallohallshalmahalmshalonhaloshalsehalshhaltshalvahalvehalwahamalhambahamedhamelhameshammyhamzahanaphancehanchhandihandshandyhangihangshankshankyhansahansehantshaolehaomahapashapaxhaplyhappihappyhapusharamhardshardyharedharemharesharimharksharlsharmsharnsharosharpsharpyharryharshhartshashyhaskshaspshastahastehastyhatchhatedhaterhateshathahathihattyhaudshaufshaughhaugohauldhaulmhaulshaulthaunshaunthausehautehavanhavelhavenhaverhaveshavochawedhawkshawmshawsehayedhayerhayeyhaylehazanhazedhazelhazerhazeshazleheadsheadyhealdhealsheameheapsheapyheardhearehearsheartheastheathheatsheatyheaveheavyhebenhebeshechtheckshederhedgehedgyheedsheedyheelsheezehefteheftsheftyheiauheidsheighheilsheirsheisthejabhejraheledhelesheliohelixhellahellohellshellyhelmsheloshelothelpshelvehemalhemeshemicheminhempshempyhencehenchhendshengehennahennyhenryhentsheparherbsherbyherdsheresherlshermahermshernsheronherosherpsherryhersehertzheryehespshestsheteshethsheuchheughheveahevelhewedhewerhewghhexadhexedhexerhexeshexylheyedhianthibashickshidedhiderhideshiemshifishighshighthijabhijrahikedhikerhikeshikoihilarhilchhillohillshillyhilsahiltshilumhilushimbohinauhindshingehingshinkyhinnyhintshioishipedhiperhipeshiplyhippohippyhiredhireehirerhireshissyhistshitchhithehivedhiverhiveshizenhoachhoaedhoagyhoardhoarshoaryhoasthobbyhoboshockshocushodadhodjahoershoganhogenhoggshoghshogohhogoshohedhoickhoiedhoikshoinghoisehoisthokashokedhokeshokeyhokishokkuhokumholdsholedholesholeyholkshollahollohollyholmeholmsholonholosholtshomashomedhomerhomeshomeyhomiehommehomoshonanhondahondshonedhonerhoneshoneyhongihongshonkshonkyhonorhoochhoodshoodyhooeyhoofshoogohoohahookahookshookyhoolyhoonshoopshoordhoorshooshhootshootyhoovehopakhopedhoperhopeshoppyhorahhoralhorashordehorishorkshormehornshornyhorsehorsthorsyhosedhoselhosenhoserhoseshoseyhostahostshotchhotelhotenhotishotlyhottehottyhouffhoufshoughhoundhourihourshousehoutshoveahovedhovelhovenhoverhoveshowayhowbehowdyhoweshowffhowfshowkshowlshowrehowsohowtohoxedhoxeshoyashoyedhoylehubbahubbyhuckshudnahududhuershuffshuffyhugerhuggyhuhushuiashuieshukouhulashuleshulkshulkyhullohullshullyhumanhumashumfshumichumidhumorhumphhumpshumpyhumushunchhundohunkshunkyhuntshurdshurlshurlyhurrahurryhursthurtshurtyhushyhuskshuskyhusoshussyhutchhutiahuzzahuzzyhwylshydelhydrahydrohyenahyenshyggehyinghykeshylashyleghyleshylichymenhymnshyndehyoidhypedhyperhypeshyphahyphyhyposhyraxhysonhytheiambiiambsibrikicersichedichesichoriciericilyicingickerickleiconsictalicticictusidantiddahiddatiddutidealideasideesidentidiomidiotidledidleridlesidlisidolaidolsidyllidylsiftarigapoiggediglooiglusignisihramiiwisikansikatsikonsileacilealileumileusiliaciliadilialiliumillerillthimageimagoimagyimamsimariimaumimbarimbedimbosimbueimideimidoimidsimineiminoimlisimmewimmitimmiximpedimpelimpisimplyimpotimproimshiimshyinaneinaptinarminboxinbyeincasincelincleincogincurincusincutindewindexindiaindieindolindowindriindueineptinerminertinferinfixinfosinfrainganingleingotinioninkedinkerinkleinlayinletinnedinnerinnieinnitinorbinputinrosinruninseeinsetinspointelinterintilintisintraintroinulainureinurninustinvarinverinwitiodiciodidiodinioniciorasiotasipponiradeirateiridsiringirkedirokoironeironsironyisbasishesisledislesisletisnaeisseiissueistleitchyitemsitheriviediviesivoryixiasixnayixoraixtleizardizarsizzatjaapsjabotjacaljacetjacksjackyjadedjadesjafasjaffajagasjagerjaggsjaggyjagirjagrajailsjakerjakesjakeyjakiejalapjaleojalopjambejambojambsjambujamesjammyjamonjamunjanesjankyjannsjannyjantyjapanjapedjaperjapesjarksjarlsjarpsjartajaruljaseyjaspejaspsjathajatisjatosjauksjaunejauntjaupsjavasjaveljawanjawedjawnsjaxiejazzyjeansjeatsjebeljedisjeelsjeelyjeepsjeerajeersjeezejefesjeffsjehadjehusjelabjellojellsjellyjembejemmyjennyjeonsjeridjerksjerkyjerryjessejessyjestsjesusjeteejetesjetonjettyjeunejewedjeweljewiejhalajheeljhilsjiaosjibbajibbsjibedjiberjibesjiffsjiffyjiggyjigotjihadjillsjiltsjimmyjimpyjingojingsjinksjinnejinnijinnsjirdsjirgajirrejismsjitisjittyjivedjiverjivesjiveyjnanajobedjobesjockojocksjockyjocosjodeljoeysjohnsjoinsjointjoistjokedjokerjokesjokeyjokoljoledjolesjoliejollojollsjollyjoltsjoltyjomonjomosjonesjongsjontyjooksjoramjortsjorumjotasjottyjotunjoualjougsjouksjoulejoursjoustjowarjowedjowlsjowlyjoyedjubasjubesjucosjudasjudgejudgyjudosjugaljugumjuicejuicyjujusjukedjukesjukusjulepjuliajumarjumbojumbyjumpsjumpyjuncojunksjunkyjuntajuntojupesjuponjuraljuratjureljuresjurisjurorjustejustsjutesjuttyjuvesjuviekaamakababkabarkabobkachakackskadaikadeskadiskafirkagoskaguskahalkaiakkaidskaieskaifskaikakaikskailskaimskaingkainskajalkakaskakiskalamkalaskaleskalifkaliskalpakaluakamaskameskamikkamiskammekanaekanalkanaskanatkandykanehkaneskangakangskanjikantskanzukaonskapaikapaskaphakaphskapokkapowkappakapurkapuskaputkaraikaraskaratkareekarezkarkskarmakarnskarookaroskarrikarstkarsykartskarzykashakasmekatalkataskatiskattikaughkaurikaurukaurykavalkavaskawaskawaukawedkayakkaylekayoskaziskazookbarskcalskeakikebabkebarkebobkeckskedgekedgykeechkeefskeekskeelskeemakeenokeenskeepskeetskeevekefirkehuakeirskelepkelimkellskellykelpskelpykeltskeltykembokembskempskemptkempykenafkenchkendokenoskentekentskepiskerbskerelkerfskerkykermakernekernskeroskerrykervekesarkestsketasketchketesketolkevelkevilkexeskeyedkeyerkhadikhadskhafskhakikhanakhanskhaphkhatskhayakhazikhedakheerkhethkhetskhirskhojakhorskhoumkhudskhulakhyalkiaatkiackkiakikiangkiasukibbekibbikibeikibeskiblakickskickykiddokiddykidelkideokidgekiefskierskievekievskightkikaykikeskikoikileykiligkilimkillskilnskiloskilpskiltskiltykimbokimetkinaskindakindskindykineskingskingykininkinkskinkykinoskiorekioskkipahkipaskipeskippakippskipsykirbykirkskirnskirrikisankissykistskitabkitedkiterkiteskithekithskitkekittykitulkivaskiwisklangklapsklettklickkliegkliksklongkloofklugeklutzknackknagsknapsknarlknarsknaurknaveknawekneadkneedkneelkneesknellkneltknickknifeknishknitskniveknobsknockknollknoopknopsknospknotsknoudknoutknowdknoweknownknowsknubsknuleknurlknurrknursknutskoalakoanskoapskobankoboskoelskoffskoftakogalkohaskohenkohlskoinekoiwikojiskokamkokaskokerkokrakokumkolaskoloskombikombukonbukondokonkskookskookykoorikopekkophskopjekoppakoraikorankoraskoratkoreskoriskormakoroskorunkoruskoseskotchkotoskotowkourakraalkrabskraftkraiskraitkrangkranskranzkrautkrayskreefkreenkreepkrengkrewekrillkriolkronakronekroonkrubikrumpkrunkksarskubiekudoskuduskudzukufiskugelkuiaskukrikukuskulakkulankulaskulfikumiskumyskunaskundskuriskurrekurtakuruskussokustikutaikutaskutchkutiskutuskuyaskuzuskvasskvellkwaaikwelakwinkkwirlkyackkyakskyangkyarskyatskyboskydstkyleskyliekylinkylixkyloekyndekyndskypeskyriekyteskythekyudolaarflaarilabdalabellabialabislabnelaborlabralaccylacedlacerlaceslacetlaceylacislackalackslackyladduladdyladedladeeladenladerladesladleladoolaerslaevolaganlagarlagerlaggylahallaharlaichlaicslaidelaidslaighlaikalaikslairdlairslairylaithlaitylakedlakerlakeslakhslakinlaksalaldylallslamaslambslambylamedlamerlameslamialammylampslanailanaslancelanchlandelandslanedlaneslankslankylantslapaslapellapinlapislapjelappalappylapselarchlardslardylareelareslarfslargalargelargolarislarkslarkylarnslarntlarumlarvalasedlaserlaseslassilassolassulassylastslatahlatchlatedlatenlaterlatexlathelathilathslathylatkelattelatuslauanlauchlaudelaudslaufslaughlaundlauralavallavaslavedlaverlaveslavralavvylawedlawerlawinlawkslawnslawnylawsylaxedlaxerlaxeslaxlylaybylayedlayerlayinlayuplazarlazedlazeslazoslazzilazzoleachleadsleadyleafsleafyleaksleakyleamsleansleantleanyleapsleaptlearelearnlearslearyleaseleashleastleatsleaveleavyleazelebenleccylecheledesledgeledgyledumleearleechleeksleepsleersleeryleeseleetsleezelefteleftsleftylegallegerlegesleggeleggoleggylegitlegnolehrslehualeirsleishlemanlemedlemellemeslemmalemmelemonlemurlendsleneslengslenislenoslenselentilentoleonelepakleperlepidlepraleptaleredlereslerpslesboleseslesoslestsletchlethelettyletupleuchleucoleudsleughlevasleveelevelleverleveslevinlevislewislexeslexislezeslezzalezzolezzylianalianeliangliardliarsliartlibelliberliborlibralibrelibrilicetlichilichtlicitlickslidarlidosliefsliegelienslierslieuslieveliferlifeslifeyliftsliganligerliggelightlignelikedlikenlikerlikeslikinlilaclillslilosliltsliltylimanlimaslimaxlimbalimbilimbolimbslimbylimedlimenlimeslimeylimitlimmalimnslimoslimpalimpslinaclinchlindslindylinedlinenlinerlineslineylingalingolingslingylininlinkslinkylinnslinnylinoslintslintylinumlinuxlionslipaslipeslipidlipinliposlippyliraslirkslirotlisesliskslislelispslistslitailitaslitedlitemliterliteslithelitholithslitielitrelivedlivenliverliveslividlivorlivreliwaaliwasllamallanoloachloadsloafsloamsloamyloansloastloathloavelobarlobbylobedlobesloboslobuslocallochelochslochylocielocislockslockylocoslocumlocuslodenlodeslodgeloessloftsloftyloganlogesloggylogialogiclogieloginlogoilogonlogoslohanloidsloinsloipeloirslokeslokeylokumlolasloledlollolollslollylologloloslomaslomedlomeslonerlongalongelongsloobylooedlooeyloofaloofslooielookslookyloomsloonsloonyloopsloopyloordlooselootslopedloperlopesloppyloralloranlordslordylorelloresloriclorislorrylosedlosellosenloserloseslossylotahlotaslotesloticlotoslotsalottalottelottolotuslouedloughlouielouisloumaloundlounsloupeloupslourelourslourylouselousyloutslovatlovedloveeloverlovesloveylovielowanlowedlowenlowerloweslowlylowndlownelownslowpslowrylowselowthlowtsloxedloxesloyallozenluachluauslubedlubeslubraluceslucidlucksluckylucreludesludicludosluffaluffslugedlugerlugeslullsluluslumaslumbilumenlummelummylumpslumpylunarlunaslunchluneslunetlungelungilungslunksluntslupinlupuslurchluredlurerlureslurexlurgilurgyluridlurkslurrylurveluserlushyluskslustslustylususlutealutedluterlutesluvvyluxedluxerluxeslweislyamslyardlyartlyaselycealyceelycralyinglymeslymphlynchlyneslyreslyriclysedlyseslysinlysislysollyssalytedlyteslythelyticlyttamaaedmaaremaarsmabanmabesmacasmacawmaccamacedmacermacesmachemachimachomachsmackamacksmaclemaconmacromactemadalmadammadarmaddymadgemadidmadlymadosmadremaedimaerlmafiamaficmaftsmagasmagesmaggsmagicmagmamagnamagotmagusmahalmahemmahismahoemahrsmahuamahwamaidsmaikomaiksmailemaillmailomailsmaimsmainsmairemairsmaisemaistmaizemajasmajatmajoemajormajosmakafmakaimakanmakarmakeemakermakesmakiemakismakosmalaemalaimalammalarmalasmalaxmaleomalesmalicmalikmalismalkymallsmalmsmalmymaltsmaltymalusmalvamalwamamakmamasmambamambomambumameemameymamiemamilmammamammymanasmanatmandimandsmandymanebmanedmanehmanesmanetmangamangemangimangomangsmangymaniamanicmaniemanismanksmankymanlymannamannymanoamanormanosmansemansomantamantemantomantsmantymanulmanusmanzomapaumapesmaplemapoumappymaqammaquimaraemarahmaralmaranmarasmaraymarchmarcsmardsmardymaresmargamargemargomargsmariamaridmarilmarkamarksmarlemarlsmarlymarmamarmsmaronmarormarramarrimarrymarsemarshmartsmaruamarvymasasmasedmasermasesmashamashymasksmasonmassamassemassymastsmastymasurmasusmasutmataimatchmatedmatermatesmateymathemathsmatinmatlomatramatsumattemattsmattymatzamatzomaubymaudsmaukamaulamaulsmaumsmaumymaundmauntmaurimausymautsmauvemauvymauzymavenmaviemavinmavismawedmawksmawkymawlamawnsmawpsmawrsmaxedmaxesmaximmaxismayanmayasmaybemayedmayormayosmaystmazacmazakmazarmazasmazedmazelmazermazesmazetmazeymazutmbarimbarsmbilambirambretmbubembugameadsmeakemeaksmealsmealymeanemeansmeantmeanymearemeasemeathmeatsmeatymebbemebosmeccamechamechsmecksmecummedalmediamedicmediimedinmedlemeechmeedsmeejameepsmeersmeetsmeffsmeidsmeikomeilsmeinsmeintmeinymeismmeithmekkamelammelasmelbamelchmeldsmeleemelesmelicmelikmellsmeloemelonmelosmeltsmeltymemesmemicmemosmenadmencemendsmenedmenesmengemengsmenilmensamensemenshmentamentomentsmenusmeousmeowsmerchmercsmercymerdemerdsmeredmerelmerermeresmergemerilmerismeritmerksmerlemerlsmerrymersemerskmesadmesalmesasmescameselmesemmesesmeshymesiamesicmesnemesonmessymestomesylmetalmetasmetedmetegmetelmetermetesmethimethomethsmethymeticmetifmetismetolmetremetromettameumsmeusemevedmevesmewedmewlsmeyntmezesmezzamezzemezzomgalsmhorrmiaismiaoumiaowmiasmmiaulmicasmichemichimichtmicksmickymicosmicramicromiddymidgemidgymidismidstmiensmieuxmievemiffsmiffymiftymiggsmightmigmamigodmihasmihismikanmikedmikesmikosmikramikvamilchmildsmilermilesmilfsmiliamilkomilksmilkymillemillsmillymilormilosmilpamiltsmiltymiltzmimedmimeomimermimesmimicmimismimsyminaeminarminasmincemincymindimindsminedminerminesmingemingimingsmingyminimminisminkeminksminnyminorminosminsemintsmintyminusminxymiraamirahmirchmiredmiresmirexmiridmirinmirknmirksmirkymirlsmirlymirosmirrlmirrsmirthmirvsmirzamisalmischmisdomisermisesmisgomiskymislsmisosmissamissymistomistsmistymitasmitchmitermitesmiteymitiemitismitremitrymittamittsmiveymivvymixedmixenmixermixesmixiemixismixtemixupmiyasmizenmizesmizzymmkaymnememoaismoakymoalsmoanamoansmoanymoarsmoatsmobbymobedmobeemobesmobeymobiemoblemobosmocapmochamochimochsmochymocksmockymocosmocusmodalmodelmodemmodermodesmodgemodiimodinmodocmodommodusmoenimoersmofosmogarmogasmoggymogosmogramoguemogulmoharmohelmohosmohrsmohuamohurmoilemoilsmoiramoiremoistmoitsmoitymojosmokermokesmokeymokismokkymokosmokusmolalmolarmolasmoldsmoldymoledmolermolesmoleymoliemollamollemollomollsmollymoloimolosmoltomoltsmoluemolvimolysmomesmomiemommamommemommymomosmompemomusmonadmonalmonasmondemondomonermoneymongomongsmonicmoniemonksmonosmonpemontemonthmontymoobsmoochmoodsmoodymooedmooeymooksmoolamoolimoolsmoolymoongmoonimoonsmoonymoopsmoorsmoorymoosemoothmootsmoovemopedmopermopesmopeymoppymopsymopusmoraemorahmoralmoranmorasmoratmoraymoreemorelmoresmorgymoriamorinmormomornamornemornsmoronmorormorphmorramorromorsemortsmorukmosedmosesmoseymosksmossomossymostemostomostsmotedmotelmotenmotesmotetmoteymothsmothymotifmotismotonmotormottemottomottsmottymotusmotzamouchmouesmoufsmouldmoulemoulsmoultmoulymoundmountmoupsmournmousemoustmousymouthmovedmovermovesmoviemowasmowedmowermowiemowramoxasmoxiemoyasmoylemoylsmozedmozesmozosmpretmradsmsasamtepemuchomucicmucidmucinmuckomucksmuckymucormucromucusmudarmuddymudgemudifmudimmudirmudramuffsmuffymuftimuggamuggsmuggymughomugilmugosmuhlymuidsmuilsmuirsmuirymuistmujikmukimmuktimulaimulchmulctmuledmulesmuleymulgamuliemullamullsmulsemulshmumbomummsmummymumphmumpsmumsymumusmunchmundsmundumungamungemungimungomungsmungymuniamunismunjamunjsmuntsmuntumuonsmuralmurasmuredmuresmurexmurghmurgimuridmurksmurkymurlsmurlymurramurremurrimurrsmurrymurthmurtimurukmurvamusarmuscamusedmuseemusermusesmusetmushamushymusicmusitmusksmuskymusosmussemussymustamusthmustsmustymutasmutchmutedmutermutesmuthamuticmutismutonmuttimuttsmutummuvvamuxedmuxesmuzakmuzzymvulamvulemvulimyallmyalsmylarmynahmynasmyoidmyomamyonsmyopemyopsmyopymyrrhmysidmysiemythimythsmythymyxosmzeesnaamsnaansnaatsnabamnabbynabesnabisnabksnablanabobnachenachonacrenadasnadirnaevenaevinaffsnagarnagasnagesnaggynagornahalnaiadnaibsnaicenaidsnaieonaifsnaiksnailsnailynainsnaiosnairanairunaivenajibnakasnakednakernakfanalasnalednallanamadnamaknamaznamednamernamesnammanamusnanasnancenancynandunannanannynanosnantenantinantonantsnantynanuanapasnapednapesnapohnapoonappanappenappynarasnarconarcsnardsnaresnaricnarisnarksnarkynarodnarranarrenasalnashinashonasisnasonnastynasusnataknatalnatchnatesnatisnattonattynatyanauchnauntnavalnavarnavednavelnavesnavewnavvynawabnawalnazarnazesnazirnazisnazzyndujaneafenealsneantneapsnearsneathneatoneatsnebbynebeknebelnechenecksneddyneebsneedsneedyneefsneeldneeleneembneemsneepsneeseneezenefienegrinegronegusneifsneighneistneivenelianelisnellynemasnemicnemnsnemptnenesnentaneonsneosaneozanepernepitneralneramnerdsnerdynerfsnerkanerksnerolnertsnertznervenervyneskinestsnestynetasnetesnetopnettanettsnettyneuksneumeneumsnevelnevernevesnevisnevusnevvynewbsnewednewelnewernewienewlynewsynewtsnexalnexinnextsnexumnexusngaiongakanganangapingatingegengomangoningramngweenibbynicadnicednicerniceynichenichtnicksnickynicolnidalnidednidesnidornidusnieceniefsniessnievenifesniffsniffynifleniftynigernigganighsnightnigreniguanihilnikabnikahnikaunilasnillsnimbinimbsnimbynimpsninerninesninjaninnyninonnintaninthnioponiozanipasnipetnippyniqabnirlsnirlyniseinisinnissenisusnitalniternitesnitidnitonnitrenitronitrynittanittonittynivalnivasnivelnixednixernixesnixienizamnjirlnkosinmolinmolsnoahsnobbynoblenoblynocksnodalnoddynodednodesnodumnodusnoelsnoemanoemenogalnoggsnoggynohownoiasnoilsnoilynointnoirenoirsnoisenoisynokesnolesnollenollsnolosnomadnomasnomennomesnomicnomoinomosnonannonasnoncenoncynondanondononesnonetnongsnonicnonisnonnanonnononnynonylnoobsnooisnooitnooksnookynoonenoonsnoopsnoosenoovenopalnorianorienorisnorksnormanormsnorthnosednosernosesnoseynoshinosirnotalnotamnotchnotednoternotesnotumnougsnoujanouldnoulenoulsnounsnounynoupsnoustnovaenovasnovelnovianovionovumnowaynowdsnowednowlsnowtsnowtynoxalnoxasnoxesnoyaunoyednoyesnrttanrtyansimanubbynubianuchanucinnuddynudernudesnudgenudgynudienudzhnuevonuffsnugaenujolnukednukesnullanullonullsnullynumbsnumennummynumpsnunksnunkynunnynunusnuquenurdsnurdynurlsnurrsnursenurtsnurtznusednusesnutsonutsynuttynyaffnyalanyamsnyingnylonnymphnyongnyssanyungnyusenyuzeoafosoakedoakenoakeroakumoaredoareroasaloasesoasisoastsoatenoateroathsoavesobangobbosobeahobeliobeseobeysobiasobiedobiitobitsobjetoboesoboleoboliobolsoccamoccuroceanocherochesochreochryockerocoteocreaoctadoctaloctanoctasoctetocticoctlioctyloculiodahsodalsodderoddlyodeonodeumodismodistodiumodoomodorsodourodumsodyleodylsofaysoffaloffedofferoffieoflagoftenofterofuroogamsogeedogeesogginoghamogiveogledogleroglesogmicogresoheloohiasohingohmicohoneoicksoidiaoiledoileroiletoinksointsoiranojimeokapiokaysokehsokiesokingokoleokrasokrugoktasolateoldenolderoldieoldlyolehsoleicoleinolentoleosoleumoleyloligooliosolivaoliveollasollavollerollieologyolonaolpaeolpesomasaomberombreombusomdahomdasomddaomdehomeesomegaomensomersomiaiomitsomlahommelomminomnesomovsomrahomulsonceroncesoncetoncusondesondolonelyonersoneryongononiononiumonkusonlaponlayonmunonnedonsenonsetontalonticooaasoobitoohedooidsoojahoomphoontsoopakoopedoopsyoorieoosesootidooyahoozedoozesoozieoozleopahsopalsopensopepeoperaoperyopgafopihiopineopingopiumopposopsatopsinopsitoptedopteropticopzitorachoracyoralsorangoransorantorateorbatorbedorbicorbitorcasorcinorderordieordosoreadorfesorfulorganorgiaorgicorgueoribiorielorigoorixaorlesorlonorlopormerorneeornisorpedorpinorrisortetorthoorvalorzososarsoscarosetroseysoshacosieroskinoslinosmicosmolosoneossiaostiaotakuotaryotherothylotiumottarotterottosoubitoucheouchtouedsouensoughtouijaoulksoumasounceoundyoupasoupedoupheouphsoureyourieouselousiaoustsoutbyoutdooutedoutenouteroutgooutieoutreoutroouttaouzelouzosovalsovaryovateovelsovensoversovertovineovismovistovoidovoliovoloovuleowareowariowcheowersowiesowingowledowlerowletownedownerownioowresowrieowsenoxbowoxeasoxersoxeyeoxideoxidsoxiesoximeoximsoxineoxlipoxmanoxmenoxteroyamaoyersozekiozenaozoneozziepaahopaalspaanspacaipacaspacaypacedpacerpacespaceypachapackspackypacospactapactspadampadaspaddopaddypadispadlepadmapadoupadrepadripaeanpaedopaeonpaganpagedpagerpagespaglepagnepagodpagripahitpahospahuspaikspailspainspaintpaipepaipspairepairspaisapaisepakaypakkapakkipakuapakulpalakpalarpalaspalaypaleapaledpalerpalespaletpalispalkipallapallspallupallypalmspalmypalpipalpspalsapalsypaluspambypampapanaxpancepanchpandapandspandypanedpanelpanespangapangspanicpanimpanirpankopankspannapannepannipannypansypantopantspantypaolipaolopapadpapalpapaspapawpaperpapespapeypappipappypapriparaeparasparchparcspardipardspardyparedparenpareoparerparespareuparevpargepargoparidparisparkaparkiparksparkyparleparlyparmaparmoparmsparolparpsparraparrsparryparsepartepartipartspartyparveparvopasagpasarpaschpaseopasespashapashmpaskapasmopaspypassepassupastapastepastspastypataspatchpatedpateepatelpatenpaterpatespathspatiapatinpatiopatkapatlypatsypattapattepattupattypatuspauaspaulspausepauxipavanpavaspavedpavenpaverpavespavidpaviepavinpavispavonpavvypawaspawawpawedpawerpawkspawkypawlspawnspaxespayedpayeepayerpayorpaysdpeacepeachpeagepeagspeakepeakspeakypealspeanspearepearlpearspeartpeasepeasypeatspeatypeavypeazepebaspecanpechspeciapeckepeckspeckypectspedalpedespedispedonpedospedropeecepeekspeekypeelspeelypeenspeentpeeoypeepepeepspeepypeerspeerypeevepeevopeggypeghspegmapegospeinepeinspeisepeisypeizepekanpekaupekeapekespekidpekinpekoepelaspelaupelchpelespelfspellspelmapelogpelonpelshpeltapeltspeluspenalpencependspendupenedpenespengopeniepenispenkspennapennepennipennypensepensypentspeolapeonspeonypeplapeplepeponpepospeppypepsipequiperaeperaiperceperchpercsperduperdypereaperesperfsperilperisperksperkyperleperlspermspermypernepernsperogperpsperryperseperspperstpertspervepervopervspervypeschpeskypesospestapestopestspestypetalpetarpeterpetitpetospetrepetripettipettopettypewedpeweepewitpeysepffttphagephangpharepharmphasephasmpheerphemephenepheonphesephialphiesphishphizzphloxphobephocaphonephonophonsphonyphoohphooophotaphotophotsphotyphphtphubsphutsphutuphwatphylaphylephymaphynxphysapiaispianipianopianspibalpicalpicaspiccypiceypichipickspickypiconpicotpicrapiculpiecepiedspiendpierspiertpietapietspietypiezopiggypightpiglypigmypiingpikaspikaupikedpikelpikerpikespikeypikispikulpilaepilafpilaopilarpilaupilawpilchpileapiledpileipilerpilespileypilinpilispillspilonpilotpilowpilumpiluspimaspimpspinaspinaxpincepinchpindapindspinedpinerpinespineypingapingepingopingspinkopinkspinkypinnapinnypinolpinonpinotpintapintopintspinuppionspionypiouspioyepioyspipalpipaspipedpiperpipespipetpipidpipispipitpippypipulpiquepiquipiraipirkspirlspirnspirogpirrepirripirrspiscopisespiskypisospissypistepitaspitchpithspithypitonpitotpitsopitsupittapittupiumapiumspivospivotpixelpixespixiepiyutpizedpizerpizespizzaplaasplaceplackplagaplageplaidplaigplainplaitplancplaneplanhplankplansplantplapsplashplasmplastplateplatsplattplatyplaudplaurplavsplayaplaysplazapleadpleaspleatplebeplebspleckpleeppleinplenapleneplenopleonpleshpletsplewsplexiplicapliedplierpliespligsplimsplingplinkplipsplishploatploceplockplodsploitplombplongplonkplookplootplopsploreplotsplotzploukploutplowsplowtployeployspluckpludspluespluffplugsplukeplumbplumeplumpplumsplumyplungplunkpluotplupsplushpluteplutoplutyplyerpneuspoachpoakapoakepoalopobbypoboypocanpochepochopockspockypodalpoddypodexpodgepodgypodiapodospoduspoemspoenapoepspoesypoetepoetspogeypoggepoggypogospoguepohedpoilupoindpointpoirepoisepokalpokedpokerpokespokeypokiepokitpolarpoledpolerpolespoleypoliopolispoljepolkapolkspollopollspollypolospoltspolyppolyspomaspombepomespommepommypomospompapompsponceponcypondspondyponesponeypongapongopongspongyponksponorpontopontspontyponzupooaypoochpoodspooedpooeypoofspoofypoohspoohypoojapookapookspoolspoolypoonspoopapoopspoopypooripoortpootspootypoovepoovypopespopiapopospoppapoppypopsypopupporaeporalporchporedporerporesporeyporgeporgyporinporksporkypornopornspornyportaporteporthportsportyporusposcaposedposerposesposetposeyposhopositposolpossepostepostspotaepotaipotchpotedpotespotinpotoopotropotsypottopottspottypoucepouchpouffpoufspoufypouispoukepoukspoulepoulppoultpoundpoupepouptpourspousypoutspoutypovospowanpowerpowiepowinpowispowltpowndpownspownypowrepowsypoxedpoxespoyaspoyntpoyoupoysepozzypraampradspragsprahupramspranaprangprankpraosprapsprasepratepratsprattpratyprausprawnprayspreakpredypreedpreempreenpreespreifprekepremspremyprentpreonpreopprepspresapresepressprestpretapreuxpreveprexypreysprialprianpriceprickpricypridepridypriedpriefprierpriesprigsprillprimaprimeprimiprimoprimpprimsprimypringprinkprintprionpriorpriseprismprisspriusprivyprizeproalproasprobeprobsprobyproddprodsproemprofsprogsproinprokeproleprollpromopromsproneprongpronkproofprookprootpropsproraproreproseprosoprossprostprosyprotoproudproulproveprowkprowlprowsproxyproynprudepruneprunopruntprunyprutapryanpryerprysepsalmpseudpshawpshutpsiaspsionpsoaepsoaipsoaspsorapsychpsyopptishptypepubbypubcopubespubicpubispubsypucanpucerpucespuckapuckspuddypudgepudgypudicpudorpudsypuduspuerspuffapuffspuffypuggypugilpuhaspujahpujaspukaspukedpukerpukespukeypukkapukuspulaopulaspuledpulerpulespulikpulispulkapulkspullipullspullypulmopulpspulpypulsepuluspulutpumaspumiepumpspumpypunaspuncepunchpungapungipungopungspungypunimpunjipunkapunkspunkypunnypuntopuntspuntypupaepupalpupaspupilpuppapuppypupuspuraopuraupurdapurdypuredpureepurerpurespurgapurgepurinpurispurlspurospurpspurpypurrepurrspurrypursepursypurtypusespushypuslepussyputasputerputidputinputonputosputtiputtoputtsputtuputtyputzapuukopuyaspuzelpuztapwnedpyatspyetspygalpygmypyinspylonpynedpynespyoidpyotspyralpyranpyrespyrexpyricpyrospyruspyuffpyxedpyxespyxiepyxispzazzqadisqaidsqajaqqanatqapikqiblaqilasqipaoqophsqormaquabsquackquadsquaffquagsquailquairquaisquakequakyqualequalmqualyquankquantquarequarkquarlquartquashquasiquassquatequatsquawkquawsquaydquaysqubitqueanqueckqueekqueemqueenqueerquellquemequenaquernqueryquesoquestquetequeuequeynqueysqueyuquibsquichquickquidsquiesquietquiffquilaquillquiltquimsquinaquinequinkquinoquinsquintquipoquipsquipuquirequirkquirlquirtquistquitequitsquoadquodsquoifquoinquoisquoitquollquonkquopsquorkquorlquotaquotequothquoukquoysquranqurshquyteraadsraakerabatrabbirabicrabidrabisracedracerracesracheracksraconradarraddiraddyradgeradgyradifradiiradioradixradonrafeeraffsraffyrafikrafiqraftsraftyragasragderagedrageeragerragesraggaraggsraggyragisragusrahedrahuiraiahraiasraidsraikeraiksrailerailsrainerainsrainyrairdraiseraitaraithraitsrajahrajasrajesrakedrakeerakerrakesrakhirakiarakisrakkiraksirakusralesrallirallyralphramalrameeramenramesrametramieraminramisrammyramonrampsramseramshramusranasranceranchrandorandsrandyranedraneeranesrangarangerangirangsrangyranidranisrankeranksrannsrannyranserantsrantyrapedrapeeraperrapesrapherapidrapinrapperapsoraredrareerarerraresrarksrasamrasasrasedraserrasesraspsraspyrasserastaratalratanratasratchratedratelraterratesratharatherathsratioratooratosrattirattyratusrauliraunsrauporavedravelravenraverravesraveyravinrawdyrawerrawinrawksrawlyrawnsraxedraxesrayahrayasrayedrayleraylsraynerayonrazairazedrazeerazerrazesrazetrazoorazorreachreactreaddreadsreadyreaisreaksrealmrealorealsreamereamsreamyreansreapsreardrearmrearsreastreatareatereaverebabrebarrebberebecrebelrebidrebitreboprebudrebusrebutrebuyrecalrecapreccereccoreccyreceprecitrecksreconrectarecterectirectorecuerecurrecutredanreddsreddyrededredesrediaredidredifredigredipredlyredonredosredoxredryredubredugreduxredyereeafreechreedereedsreedyreefsreefyreeksreekyreelsreelyreemsreensreerdreestreevereezerefanrefedrefelreferrefforefisrefitrefixreflyrefryregalregarregesregetregexreggoregiaregieregleregmaregnaregosregotregurrehabrehemreifsreifyreignreikireiksreinereingreinkreinsreirdreistreiverejasrejigrejonrekedrekesrekeyrelaxrelayreletrelicrelierelitrellorelosremanremapremenremetremexremitremixremourenalrenayrendsrendurenewreneyrengarengsrenigreninrenksrennerenosrenterentsreoilreorgrepasrepatrepayrepegrepelrepenrepinreplareplyreposrepotreppsreprorepunreputreranrerigrerunresamresatresawresayreseeresesresetresewresidresinresitresodresolresowrestorestsrestyresueresusretagretamretaxretchretemretiaretieretinretipretoxretroretryreunereupsreuserevelrevetrevierevowrevuerewanrewaxrewedrewetrewinrewonrewthrexesrezesrhabdrheasrheidrhemerheumrhiesrhimerhinerhinorhodyrhombrhonerhumbrhymerhymyrhynerhytariadsrialsriantriatariatoribasribbyribesricedricerricesriceyricherichtricinricksriderridesridgeridgyridicrielsriemsrieveriferriffsriffyriflerifteriftsriftyriggsrightrigidrigmorigolrigorrikkarikwariledrilesrileyrillerillsrillyrimaerimedrimerrimesrimonrimusrincerindsrindyrinesringeringsringyrinksrinseriojarioneriotsriotyripedripenriperripesrippsriqqsrisenriserrisesrishirisksriskyrispsristsrisusritesritherittsritzyrivalrivasrivedrivelrivenriverrivesrivetriyalrizasroachroadsroadyroakeroakyroamsroansroanyroarsroaryroastroaterobborobedroberrobesrobinroblerobotrobugroburrocherocksrockyrodedrodeorodesrodnyroersroganrogerrogueroguyrohanrohesrohunrohusroidsroilsroilyroinsroistrojakrojisrokedrokerrokesrokeyrokosrolagroleorolesrolfsrollsrollyromalromanromeoromerrompsrompurompyronderondoroneoronesroninronneronterontsronukroodsroofsroofyrooksrookyroomsroomyroonsroopsroopyroosarooseroostrootsrootyropedroperropesropeyroqueroralroresroricroridrorierortsrortyrosalroscorosedrosesrosetrosharoshirosinrositrospsrossarossorostirostsrotalrotanrotasrotchrotedrotesrotisrotlsrotonrotorrotosrottarotterottorottyrouenrouesrouetroufsrougeroughrougyrouksroukyrouleroulsroumsroundroupsroupyrouseroustrouterouthroutsrovedrovenroverrovesrowanrowdyrowedrowelrowenrowerrowetrowierowmerowndrownsrowthrowtsroyalroyetroyneroystrozesrozetrozitruachruanarubairubanrubbyrubelrubesrubinrubiorublerubliruborrubusrucheruchyrucksrudasruddsruddyruderrudesrudierudisruedaruersrufferuffsruffyrufusrugaerugalrugasrugbyruggyruiceruingruinsrukhsruledrulerrulesrullyrumalrumbarumborumenrumesrumlyrummyrumorrumporumpsrumpyruncerunchrundsrunedrunerrunesrungsrunicrunnyrunosruntsruntyrunupruoterupeerupiaruralrurpsrurusrusasrusesrushyrusksruskyrusmarusserustsrustyruthsrutinruttyruvidryalsrybatryijiryijyrykedrykesrymerrymmeryndsryotiryotsryperrypinrytheryugisaagssabalsabedsabersabessabhasabinsabirsabjisablesabossabotsabrasabresabzisackssacrasacresaddosaddysadessadhesadhusadicsadissadlysadossadzasaetasafedsafersafessagarsagassagersagessaggysagossagumsahabsahebsahibsaicesaicksaicssaidssaigasailssaimssainesainssaintsairssaistsaithsajousakaisakersakessakiasakissaktisaladsalalsalassalatsalepsalessaletsalicsalissalixsallesallysalmisalolsalonsalopsalpasalpssalsasalsesaltosaltssaltysaludsaluesalutsalvesalvosamansamassambasambosameksamelsamensamessameysamfisamfusammysampisampssanadsandssandysanedsanersanessangasanghsangosangssankosansasantosantssaolasapansapidsaporsappysaransardssaredsareesargesargosarinsarirsarissarkssarkysarodsarossarussarvosasersasinsassesassysataisataysatedsatemsatersatessatinsatissatyrsaubasaucesauchsaucysaughsaulssaultsaunasaunfsauntsaurysautesautssauvesavedsaversavessaveysavinsavorsavoysavvysawahsawedsawersaxessayassayedsayeesayersayidsaynesayonsaystsazesscabsscadsscaffscagsscailscalascaldscalescallscalpscalyscampscamsscandscansscantscapascapescapiscarescarfscarpscarsscartscaryscathscatsscattscaudscaupscaurscawssceatscenascendscenescentschavschifschmoschulschwascifiscindscionsciresclimscobescodyscoffscogsscoldsconescoogscoopscootscopascopescopsscorescornscorpscotescotsscougscoupscourscoutscowlscowpscowsscrabscraescragscramscranscrapscratscrawscrayscreescrewscrimscripscrobscrodscrogscrooscrowscrubscrumscubascudiscudoscudsscuffscuftscugssculkscullsculpsculsscumsscupsscurfscursscusescutascutescutsscuzzscyessdaynsdeinsealsseameseamsseamyseanssearesearsseaseseatsseazesebumseccosechssectssedansedersedessedgesedgysedumseedsseedyseeksseeldseelsseelyseemsseepsseepyseerssefersegarsegassegnisegnosegolsegosseguesehriseifsseilsseineseirsseiseseismseityseizaseizesekossektsselahselesselfsselfyselkysellasellesellsselvasemassemeesemensemessemiesemissenassendssenessenexsengisennasenorsensasensesensisensusentesentisentssenvysenzasepadsepalsepiasepicsepoysepposeptaseptsseracseraiseralseredsererseresserfssergeseriasericserifserinserirserksseronserowserraserreserrsserryserumserveservoseseysessasetaesetalsetersethssetonsettssetupsevaksevenseversevirsewansewarsewedsewelsewensewersewinsexedsexersexessexorsextosextsseyensezesshackshadeshadsshadyshaftshagsshahsshakashakeshakoshaktshakyshaleshallshalmshaltshalyshamashameshamsshandshankshansshapeshapsshardsharesharksharnsharpshartshashshaulshaveshawlshawmshawnshawsshayashaysshchisheafshealshearsheasshedssheelsheensheepsheersheetsheikshelfshellshendshengshentsheolsherdsheresheroshetsshevashewnshewsshiaishiedshielshiershiesshiftshillshilyshimsshineshinsshinyshiokshipsshireshirkshirrshirsshirtshishshisoshistshiteshitsshiurshivashiveshivsshlepshlubshmekshmoeshoalshoatshockshoedshoershoesshogishogsshojishojosholashoneshonkshookshoolshoonshoosshootshopeshopsshoreshorlshornshortshoteshotsshottshoudshoutshoveshowdshownshowsshowyshoyushredshrewshrisshrowshrubshrugshtarshtikshtumshtupshubashuckshuleshulnshulsshunsshuntshurashushshuteshutsshwasshyershylysialssibbssibiasibylsicessichtsickosickssickysidassidedsidersidessideysidhasidhesidlesiegesieldsienssientsiethsieursievesiftssighssightsigilsiglasigmasignasignssigrisijossikassikersikessildssiledsilensilersilessilexsilkssilkysillssillysilossiltssiltysilvasimarsimassimbasimissimpssimulsincesindssinedsinessinewsingesingssinhssinkssinkysinsisinussipedsipessippysiredsireesirensiressirihsirissirocsirrasirupsisalsisessissysistasistssitarsitchsitedsitessithesitkasitupsitussiversixersixessixmosixtesixthsixtysizarsizedsizelsizersizesskagsskailskaldskankskarnskartskateskatsskattskawsskeanskearskedsskeedskeefskeenskeerskeesskeetskeevskeezskeggskegsskeinskelfskellskelmskelpskeneskensskeosskepsskermskerssketsskewsskidsskiedskierskiesskieyskiffskillskimoskimpskimsskinkskinsskintskiosskipsskirlskirrskirtskiteskitsskiveskivysklimskoalskobeskodyskoffskofsskogsskolsskoolskortskoshskranskrikskrooskuasskugsskulkskullskunkskyedskyerskyeyskyfsskyreskyrsskyteslabsslacksladeslaesslagsslaidslainslakeslamsslaneslangslankslantslapsslartslashslateslatsslatyslaveslawsslaysslebssledssleeksleepsleersleetsleptslewssleyssliceslickslideslierslilyslimeslimsslimyslingslinkslipeslipssliptslishslitsslivesloanslobssloesslogssloidslojdslokaslomosloomsloopslootslopeslopsslopyslormsloshslothslotssloveslowssloydslubbslubssluedsluessluffslugssluitslumpslumsslungslunkslurbslurpslurssluseslushslutsslyerslylyslypesmaaksmacksmaiksmallsmalmsmaltsmarmsmartsmashsmazesmearsmeeksmeessmeiksmekesmellsmeltsmerksmewssmicksmilesmilysmirksmirrsmirssmitesmithsmitssmizesmocksmogssmokesmokosmokysmoltsmoorsmootsmoresmorgsmotesmoutsmowtsmugssmurssmushsmutssnabssnacksnafusnagssnailsnakesnakysnapssnaresnarfsnarksnarlsnarssnarysnashsnathsnawssneadsneaksneapsnebssnecksnedssneedsneersneessnellsnibssnicksnidesniedsniessniffsniftsnigssnipesnipssnipysnirtsnitssnivesnobssnodssnoeksnoepsnogssnokesnoodsnooksnoolsnoopsnootsnoresnortsnotssnoutsnowksnowssnowysnubssnucksnuffsnugssnushsnyessoakssoapssoapysoaresoarssoavesobassobersocassocessociasockosockssoclesodassoddysodicsodomsofarsofassoftasoftssoftysogersoggysohursoilssoilysojassojussokahsokensokessokolsolahsolansolarsolassoldesoldisoldosoldssoledsoleisolersolessolidsolonsolossolumsolussolvesomansomassonarsoncesondesonessongosongssongysonicsonlysonnesonnysonsesonsysooeysookssookysoolesoolssoomssoopssootesoothsootssootysophssophysoporsoppysoprasoralsorassorbisorbosorbssordasordosordssoredsoreesorelsorersoressorexsorgosornssorrasorrysortasortssorussothssotolsottosoucesouctsoughsoukssoulssoulysoumssoundsoupssoupysourssousesouthsoutssowarsowcesowedsowersowffsowfssowlesowlssowmssowndsownesowpssowsesowthsoxessoyassoylesoyuzsozinspacespackspacyspadespadospadsspaedspaerspaesspagsspahispailspainspaitspakespaldspalespallspaltspamsspanespangspankspansspardsparesparksparsspartspasmspatespatsspaulspawlspawnspawsspaydspaysspazaspazzspeakspealspeanspearspeatspeckspecsspectspeedspeelspeerspeilspeirspeksspeldspelkspellspeltspendspentspeosspermspeshspetsspeugspewsspewyspialspicaspicespickspicsspicyspidespiedspielspierspiesspiffspifsspikespiksspikyspilespillspiltspimsspinaspinespinkspinsspinyspirespirtspiryspitespitsspitzspivssplatsplaysplitsplogspodespodsspoilspokespoofspookspoolspoomspoonspoorspootsporesporksportsposasposhsposospotsspoutspradspragspratsprayspredspreesprewsprigspritsprodsprogspruesprugspudsspuedspuerspuesspugsspulespumespumyspunkspurnspursspurtsputaspyalspyresquabsquadsquatsquawsqueesquegsquibsquidsquitsquizsrslystabsstackstadestaffstagestagsstagystaidstaigstainstairstakestalestalkstallstampstandstanestangstankstansstaphstapsstarestarkstarnstarrstarsstartstarystashstatestatsstatustaunstavestawsstayssteadsteakstealsteamsteanstearsteddstedestedssteedsteeksteelsteemsteensteepsteersteezsteiksteilsteinstelastelestellstemestemsstendstenostensstentstepssteptsteresternstetsstewsstewysteysstichstickstiedstiesstiffstilbstilestillstiltstimestimsstimystingstinkstintstipastipestirestirkstirpstirsstivestivystoaestoaistoasstoatstobsstockstoepstogsstogystoicstoitstokestolestolnstomastompstondstonestongstonkstonnstonystoodstookstoolstoopstoorstopestopsstoptstorestorkstormstorystossstotsstottstounstoupstourstoutstovestownstowpstowsstradstraestragstrakstrapstrawstraystrepstrewstriastrigstrimstripstropstrowstroystrumstrutstubsstuckstucsstudestudsstudystuffstullstulmstummstumpstumsstungstunkstunsstuntstupastupesturesturtstushstyedstyesstylestylistylostymestymystyrestytesuavesubahsubaksubassubbysubersubhasuccisuckssuckysucresudansuddssudorsudsysuedesuentsuerssuetesuetssuetysugansugarsughssugossuhursuidssuingsuintsuitesuitssujeesukhssukissukuksulcisulfasulfosulkssulkysullssullysulphsulussumacsumissummasumossumphsumpssunissunkssunnasunnssunnysuntssunupsuonasupedsupersupessuprasurahsuralsurassuratsurdssuredsurersuressurfssurfysurgesurgysurlysurrasusedsusessushisusussutorsutrasuttaswabsswackswadsswageswagsswailswainswaleswalyswamiswampswamyswangswankswansswapsswaptswardswareswarfswarmswartswashswathswatsswaylswaysswealswearsweatswedesweedsweelsweepsweersweessweetsweirswellsweltsweptswerfsweysswiesswiftswigsswileswillswimsswineswingswinkswipeswireswirlswishswissswithswitsswiveswizzswobsswoleswollswolnswoonswoopswopsswoptswordsworeswornswotsswounswungsybbesybilsyboesybowsyceesycessyconsyedssyenssykersykessylissylphsylvasymarsynchsyncssyndssynedsynessynodsynthsypedsypessyphssyrahsyrensyrupsysopsythesyvertaalstaatatabactabbytabertabestabidtabistablatabletablstabootabortabostabuntabustacantacestacettachetachitachotachstacittackstackytacostactstadahtaelstaffytafiataggytagmataguatahastahrstaigataigstaikotailstainstainttairataishtaitstajestakastakentakertakestakhitakhttakintakistakkytalaktalaqtalartalastalcstalcytaleatalertalestaliktalkstalkytallstallytalmatalontalpataluktalustamaltamastamedtamertamestamintamistammytampstanastangatangitangotangstangytanhstaniatankatankstankytannatansutansytantetantitantotantytapastapedtapentapertapestapettapirtapistappatapustarastardotardstardytaredtarestargatargetarkatarnstaroctaroktarostarottarpstarretarrytarsetarsitartetartstartytarzytasartascatasedtasertasestaskstassatassetassotastetastotastytatartatertatestathstatietatoutattstattytatustaubetauldtaunttauontaupetautstautytavahtavastavertawaftawaitawastawedtawertawietawnytawsetawtstaxedtaxertaxestaxistaxoltaxontaxortaxustayratazzatazzeteachteadeteadsteaedteakstealsteamstearstearyteaseteatsteazetechstechytectatecumteddyteelsteemsteendteeneteensteenyteersteethteetsteffsteggsteguategusteheetehrsteiidteilsteindteinstekketelaetelcotelestelexteliatelictellstellyteloitelostemedtemestempitempotempstempttemsetenchtendstendutenestenettengeteniatennetennotennytenontenortensetenthtentstentytenuetepaltepastepeetepidtepoyteraiterasterceterekteresterfeterfstergatermsterneternsterraterreterrytersetertsterzateslatestatesteteststestytetestethstetratetriteuchteughtewedteweltewittexastexestextatextsthackthagithaimthalethalithanathanethangthankthansthanxtharmtharsthawsthawtthawythebethecatheedtheektheestheftthegntheictheintheirthelfthemathemethenstheortheowtherethermthesethespthetathetethewsthewythickthiefthighthigsthilkthillthinethingthinkthinsthiolthirdthirlthofttholetholithongthornthorothorpthosethotsthousthowlthraethrawthreethrewthridthripthrobthroethrowthrumthudsthugsthujathumbthumpthunkthurlthuyathymethymithymytianstiaratiaretiarstibiaticalticcaticedticestichytickstickytidaltiddytidedtidestiefstierstiffstifostiftstigertigestighttigontikastikestikiatikistikkatilaktildetiledtilertilestillstillytilthtiltstimbotimedtimertimestimidtimontimpstinastincttindstineatinedtinestingetingstinkstinnytintotintstintytipistippytipsytipuptiredtirestirlstirostirrstirthtitantitartitastitchtitertithetithititintitirtitistitletitretittytituptiyintiynstizestizzytoadstoadytoasttoazetockstockytocostodaytoddetoddytodeatodostoeastoffstoffytoftstofustogaetogastogedtogestoguetohostoidytoiletoilstoingtoisetoitstoitytokaytokedtokentokertokestokostolantolartolastoledtolestollstollytoltstolustolyltomantombotombstomentomestomiatomintommetommytomostomoztonaltonditondotonedtonertonestoneytongatongstonictonkatonkstonnetonustoolstoomstoonstoothtootstopaztopedtopeetopektopertopestophetophitophstopictopistopoitopostoppytoquetorahtorantorastorchtorcstorestorictoriitorostorottorrstorsetorsitorsktorsotortatortetortstorustosastosedtosestoshytossytosyltotaltotedtotemtotertotestottytouchtoughtoukstounstourstousetousytoutstouzetouzytowaitowedtoweltowertowietownotownstownytowsetowsytowtstowzetowzytoxictoxintoyedtoyertoyontoyostozedtozestozietrabstracetracktracttradetradstradytragatragitragstragutraiktrailtraintraittramptramstranktranqtranstranttrapetrapotrapstrapttrashtrasstratstratttravetrawltrayftraystreadtreattrecktreedtreentreestrefatreiftrekstrematremstrendtresstresttretstrewstreyftreystriactriadtrialtribetricetricktridetriedtriertriestrifatrifftrigotrigstriketrildtrilltrimstrinetrinstrioltriortriostripetripstripytristtritetroadtroaktroattrocktrodetrodstrogstroistroketrolltromptronatronctronetronktronstrooptrooztropetropotrothtrotstrouttrovetrowstroystrucetrucktruedtruertruestrugotrugstrulltrulytrumptrunktrusstrusttruthtryertryketrymatrypstrysttsadetsaditsarstskedtsubatsubotuanstuarttuathtubaetubaltubartubastubbytubedtubertubestuckstufastuffetuffstuftstuftytugratuiletuinatuismtuktutulestuliptulletulpatulpstulsitumidtummytumortumpstumpytunastundstunedtunertunestungstunictunnytupektupiktupletuqueturboturdsturfsturfyturksturmeturmsturnsturntturonturpsturrstushytuskstuskytuteetutestutortuttituttytutustuxestuyertwaestwaintwalstwangtwanktwatstwaystweaktweedtweeltweentweeptweertweettwerktwerptwicetwiertwigstwilltwilttwinetwinktwinstwinytwiretwirktwirltwirptwisttwitetwitstwixttwocstwoertwonktwyertyeestyerstyingtyiyntykestylertympstyndetynedtynestypaltypedtypestypeytypictypostyppstyptotyrantyredtyrestyrostythetzarsubacsubityudalsudderudonsudyogugaliuggeduhlanuhuruukaseulamaulansulcerulemaulminulmosulnadulnaeulnarulnasulpanultraulvasulyieulzieumamiumbelumberumbleumbosumbraumbreumiacumiakumiaqummahummasummedumpedumphsumpieumptyumrahumrasunagiunaisunaptunarmunaryunausunbagunbanunbarunbedunbidunboxuncapuncesunciauncleuncosuncoyuncusuncutundamundeeunderundidundosundueundugunethunfedunfitunfixungagungetungodungotungumunhatunhipunicaunifyunionuniosuniteunitsunityunjamunkedunketunkeyunkidunkutunlapunlawunlayunledunlegunletunlidunlitunmadunmanunmetunmewunmixunodeunoldunownunpayunpegunpenunpinunplyunpotunputunredunridunrigunripunsawunsayunseeunsetunsewunsexunsodunsubuntaguntaxuntieuntiluntinunwedunwetunwitunwonunzipupbowupbyeupdosupdryupendupfulupjetuplayupleduplituppedupperupranuprunupseeupsetupseyuptakupteruptieuraeiuraliuraosurareurariuraseurateurbanurbexurbiaurdeeurealureasuredoureicureidurenaurenturgedurgerurgesurialurineuriteurmanurnalurnedurpedursaeursidursonurubuurupaurvasusageusensusersusetausherusingusneausnicusqueustadusterusualusureusurpusuryuteriuteroutileutteruvealuveasuvulavacasvacayvacuavacuivacuovadasvadedvadesvadgevagalvaguevagusvaidsvailsvairevairsvairyvajravakasvakilvalesvaletvalidvalisvallivalorvalsevaluevalvevampsvampyvandavanedvanesvangavangsvantsvapedvapervapesvapidvaporvaranvarasvardavardovardyvarecvaresvariavarixvarnavarusvarvevasalvasesvastsvastyvatasvathavaticvatjevatosvatusvauchvaultvauntvautevautsvawtevaxesvealevealsvealyveenaveepsveersveeryveganvegasvegesveggovegievegosvehmeveilsveilyveinsveinyvelarveldsveldtvelesvellsvelumvenaevenalvenasvendsvenduveneyvengeveninvenomventiventsvenuevenusverbaverbsverdevergeverraverreverryversaverseversoverstvertevertsvertuvervevespavestavestsvetchveuvevevesvexedvexervexesvexilvezirvialsviandvibedvibesvibexvibeyvicarvicedvicesvichyvicusvideoviersvieuxviewsviewyvifdaviffsvigasvigiavigilvigorvildevilervillavillevillivillsvimenvinalvinasvincavinedvinervinesvinewvinhovinicvinnyvinosvintsvinylviolavioldviolsviperviralviredvireoviresvirgavirgevirgoviridvirlsvirtuvirusvisasvisedvisesvisievisitvisnavisnevisonvisorvistavistovitaevitalvitasvitexvitrovittavivasvivatvivdavivervivesvividvivosvivrevixenvizirvizorvlastvleisvliesvlogsvoarsvoblavocabvocalvocesvoddyvodkavodouvodunvoemavogievoguevoicevoicivoidsvoilavoilevoipsvolaevolarvoledvolesvoletvolkevolksvoltavoltevoltivoltsvolvavolvevomervomitvotedvotervotesvouchvougevouluvowedvowelvowervoxelvoxesvozhdvraicvrilsvroomvrousvrouwvrowsvuggsvuggyvughsvughyvulgovulnsvulvavuttyvygievyingwaacswackewackowackswackywadaswaddswaddywadedwaderwadeswadgewadiswadtswaferwaffswaftswagedwagerwageswaggawagonwagyuwahaywaheywahoowaidewaifswaiftwailswainswairswaistwaitewaitswaivewakaswakedwakenwakerwakeswakfswaldowaldswaledwalerwaleswaliewaliswalkswallawallswallywaltywaltzwamedwameswamuswandswanedwaneswaneywangswankswankywanlewanlywannawantawantswantywanzewaqfswarbswarbywardswaredwareswarezwarkswarmswarnswarpswarrewarstwartswartywaseswashiwashywasmswaspswaspywastewastswatapwatchwaterwattswauffwaughwaukswaulkwaulswaurswavedwaverwaveswaveywawaswaweswawlswaxedwaxenwaxerwaxeswayedwazirwazoowealdwealsweambweanswearswearyweavewebbyweberwechtwedelwedgewedgyweedsweedyweeisweekeweeksweelsweemsweensweenyweepsweepyweestweeteweetswefteweftsweidsweighweilsweirdweirsweiseweizewekaswelchweldswelkewelkswelktwellswellywelshweltswembswenchwendswengewennywentswerfsweroswershwestswetaswetlywexedwexeswhackwhalewhamowhamswhangwhapswharewharfwhatawhatswhaupwhaurwhealwhearwheatwheekwheelwheenwheepwheftwhelkwhelmwhelpwhenswherewhetswhewswheyswhichwhidswhieswhiffwhiftwhigswhilewhilkwhimswhinewhinswhinywhioswhipswhiptwhirlwhirrwhirswhishwhiskwhisswhistwhitewhitswhitywhizzwholewhompwhoofwhoopwhootwhopswhorewhorlwhortwhosewhosowhowswhumpwhupswhydawiccawickswickywiddywidenwiderwideswidowwidthwieldwielswifedwifeswifeywifiewiftswiftywiganwiggawiggywightwikiswilcowildswiledwileswilgawiliswiljawillswillywiltswimpswimpywincewinchwindswindywinedwineswineywingewingswingywinkswinkywinnawinnswinoswinzewipedwiperwipeswiredwirerwireswirrawirriwisedwiserwiseswishawishtwispswispywistswitanwitchwitedwiteswithewithswithywittywivedwiverwiveswizenwizeswizzowoadswoadywoaldwockswodgewodgywofulwojuswokenwokerwokkawoldswolfswollywolvewomanwomaswombswombywomenwomynwongawongiwonkswonkywontswoodswoodywooedwooerwoofswoofywooldwoolswoolywoonswoopswoopywoosewooshwootzwoozywordswordyworksworkyworldwormswormyworryworseworstworthwortswouldwoundwovenwowedwoweewowsewoxenwrackwrangwrapswraptwrastwratewrathwrawlwreakwreckwrenswrestwrickwriedwrierwrieswringwristwritewritswrokewrongwrootwrotewrothwrungwryerwrylywuddywuduswuffswullswungawurstwuseswushuwussywuxiawyledwyleswyndswynnswytedwyteswythexebecxeniaxenicxenonxericxeroxxerusxoanaxolosxraysxviiixylanxylemxylicxylolxylylxystixystsyaarsyaassyabasyabbayabbyyaccayachtyackayacksyaddayaffsyageryagesyagisyagnayahooyairdyajnayakkayakowyalesyamenyampayampyyamunyandyyangsyanksyapokyaponyappsyappyyarakyarcoyardsyareryarfayarksyarnsyarrayarrsyartayartoyatesyatrayaudsyauldyaupsyawedyaweyyawlsyawnsyawnyyawpsyayasyboreycladycledycondydradydredyeadsyeahsyealmyeansyeardyearnyearsyeastyecchyechsyechyyedesyeedsyeeekyeeshyeggsyelksyellsyelmsyelpsyeltsyentayenteyerbayerdsyerksyesesyesksyestsyestyyetisyettsyeuchyeuksyeukyyevenyevesyewenyexedyexesyfereyieldyikedyikesyillsyinceyipesyippyyirdsyirksyirrsyirthyitesyitieylemsylideylidsylikeylkesymoltympesyobboyobbyyocksyodelyodhsyodleyogasyogeeyoghsyogicyoginyogisyohahyohayyoickyojanyokanyokedyokegyokelyokeryokesyokulyolksyolkyyolpsyomimyompsyonicyonisyonksyonnyyoofsyoopsyoposyoppoyoresyorgayorksyorpsyouksyoungyournyoursyourtyouseyouthyowedyowesyowieyowlsyowsayowzayoyosyraptyrentyrivdyrnehysameytostyuansyucasyuccayucchyuckoyucksyuckyyuftsyugasyukedyukesyukkyyukosyulanyulesyummoyummyyumpsyuponyuppyyurtayurtsyuzuszabrazackszaidazaidezaidyzairezakatzamaczamakzamanzambozamiazamiszanjazantezanzazanzezappyzardazarfszariszatiszawnszaxeszaydezayinzazenzealszebeczebrazebubzebuszedaszeerazeinszendozerdazerkszeroszestszestyzetaszexeszezeszhomozhushzhuzhzibetziffsziganzikrszilaszilchzillazillszimbizimbszincozincszincyzinebzineszingszingyzinkezinkyzinoszippozippyziramzitiszittyzizelzizitzlotezlotyzoaeazoboszobuszoccozoeaezoealzoeaszoismzoistzokorzollezombizonaezonalzondazonedzonerzoneszonkszooeazooeyzooidzookszoomszoomyzoonszootyzoppazoppozorilzoriszorrozorsezoukszoweezowiezuluszupanzupaszuppazurfszuzimzygalzygonzymeszymic"
  log_str_1 db "guess "
  log_str_2 db " eliminates "
  log_str_3 db " words on average", 0xA
  ; literal 36 + 1 ending byte + 5 letters from guess = 42

section .bss
  ; each word is 8 bytes (left 3 are 0, right 5 are u8 letters)
  ; 14855 words * 8 = 118840 bytes
  words_encoded resb 118840
  ; each bitmap needs to store 26*11 bits via 3 XMM registers. (16*3 = 48 bytes)
  ; there are 14855 bitmaps. 14855*48 = 713040
  alignb 16 ; yay! this works. now ptest doesnt give an exception.
  cached_bitmaps: resb 713040