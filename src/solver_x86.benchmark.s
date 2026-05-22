; MARK: Benchmarks

BENCHMARK_WORDS equ 5000 ; max 14855
; modifies: a bunch
benchmark:
  push rbp
  sub rsp, 8
  lea r14, [rel words_encoded]
  lea r15, [rel possible_secrets]

  MSTART 0
  mov r12, 0
  .for_PG1:
    mov rdi, [r14 + r12*8] ; pg
    mov r13, 0
    .for_PS1:
      mov rsi, [r15 + r13*8] ; ps

      call get_colors

      inc r13
      cmp r13, BENCHMARK_WORDS
      jne .for_PS1
    inc r12
    cmp r12, BENCHMARK_WORDS
    jne .for_PG1
  MEND 0, "Colors"

  MSTART 0
  mov rbp, 0
  .for_PG2:
    lea r14, [rel words_encoded]
    mov rdi, [r14 + rbp*8] ; pg
    mov r13, 0
    .for_PS2:
      mov rsi, [r15 + r13*8] ; ps

      call get_colors
      call make_bitmask

      inc r13
      cmp r13, BENCHMARK_WORDS
      jne .for_PS2
    inc rbp
    cmp rbp, BENCHMARK_WORDS
    jne .for_PG2
  MEND 0, "Colors + Bitmasks"

  MSTART 0
  mov qword [rsp], 0
  .for_PG3:
    lea r14, [rel words_encoded]
    mov rdi, [r14 + r12*8] ; pg
    mov rbp, 0
    .for_PS3:
      mov rsi, [r15 + rbp*8] ; ps

      call get_colors
      call make_bitmask
      mov r10, 0 ; counter
      lea rbx, [rel cached_bitmaps] ; base

      .for_another_PS3:
        lea r13, [rel possible_secrets]
        mov r13, [r13 + r10*8]
        shr r13, 40
        imul r13, r13, 48

        ptest xmm0, [rbx + r13]
        jne .word_eliminated
        ptest xmm1, [rbx + r13 + 16]
        jne .word_eliminated
        ptest xmm2, [rbx + r13 + 32]
        je .word_not_eliminated

        .word_eliminated:
        
        .word_not_eliminated:

        inc r10
        cmp r10, BENCHMARK_WORDS
        jne .for_another_PS3
      
      inc rbp
      cmp rbp, BENCHMARK_WORDS
      jne .for_PS3
    inc qword [rsp]
    cmp qword [rsp], BENCHMARK_WORDS
    jne .for_PG3
  MEND 0, "Colors + Bitmasks + Elimination"
  add rsp, 8
  pop rbp
  ret