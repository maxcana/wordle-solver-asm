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


debug:
  push rdi
  push rsi
  mov rdi, msg_size
  lea rsi, [rel msg]
  call win64_print
  pop rsi
  pop rdi
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
  for_PG:
    lea rax, [rel words_encoded]
    mov rdi, [r12*8 + rax] ; pg (last 5 bytes, ignore first 3)

    xor r10d,r10d ; total_elim
    xor r13d,r13d
    for_PS:
      lea rbx, [rel words_encoded]
      mov rsi, [rbx + r13*8] ; ps
      call get_colors ; r8 - colors in the form 00 00 00 01 02 00 02 01
  
      ; encode 'positions' section of bitmask
      mov r9, 5
      mov rax, rdi ; copy pg into rax
      for_ltr_in_pg: ; iterate right to left (r9 from 4 -> 0)
        dec r9
        ; r8b = colors[r9]
        ; al = pg[r9]
  
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
  
        movzx rbx, r8b; rbx = color (zero-extended). (0,1,2)
        lea r15, [rel jmp_table] ; temp
        jmp qword [r15 + rbx*8]
  
        gray:
          mov rbx,0x01
          movzx rcx,al
          shl rbx,cl
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
          inc byte [rsp+rbx]
  
          imul rbx, r9, 26 ; left
          imul rcx, r9, 26 ; right
          add rcx, 25
  
          call write_raw_bit_sequence ; rbx - left, rcx - right.
  
          movzx rbx, al
          imul rcx, r9, 26
          add rbx, rcx
  
          call write_raw_bit
  
        for_ltr_in_pg_end:
  
        shr r8, 8 ; drop last color
        shr rax, 8 ; drop last letter
  
        test r9, r9
        jne for_ltr_in_pg
      
      ; encode 'counts' section
      mov r9, 5
      for_ltr_in_pg_2:
        dec r9
        ; r8b = colors[r9] color
        ; al = pg[r9] letter
        movzx rcx, al
        ; letter has maximum = leftmost bit of eax == 1. 
        ; cmp eax, 0b100... or simply cmp eax, 0.
        mov eax,edx; copy ltrs_with_maximum array (26 bits) (right-to-left)
        shr eax, cl
        shl eax, 31
        mov rdx, [rsp+rcx] ; rdx = min
    
        xor r11d,r11d
        for_count: ; r11 = count (0-5)
          cmp eax, 0
          je no_max
          
          has_max:
          cmp rdx, r11
          jne write_bit
          je continue
          
          no_max:
          cmp rdx, r11
          jbe continue
          
          write_bit:
            imul rbx, r9, 26
            add rbx, 130 ; count section offset
            add rbx, rcx ; rcx = al
            call write_raw_bit
          
          continue:
          inc r11
          cmp r11, 6
          jne for_count
        
        cmp r9, 0
        jne for_ltr_in_pg_2
      
      add rsp, 32
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
        inc r10 ; add to total_elim
        
        word_not_eliminated:

        add rbx, 48
        dec r9
        jne for_another_PS
      
      inc r13
      cmp r13, 14855
      jne for_PS
  
    mov rdx, 41 ; rdx: length of string to print

    ; write " words on average", 0xA
    mov r15, rsp ; copy old rsp
    mov rcx, 18
    log_3_loop:
      lea rbx, [rel log_str_3]
      mov al, byte [rbx+rcx]
      dec rsp
      mov [rsp], al
      dec rcx
      jne log_3_loop
    
    
    ; write # eliminated words
    log_int_loop:
      mov edx, 0 ; higher 32 bits of dividend
      mov eax, r10d ; lower 32 bits of dividend
      mov ecx, 10 ; divisor
      div ecx 
      ; eax is quotient
      ; edx is remainder
      mov r10d, eax
      dec rsp
      mov [rsp], dl
      inc rdx
      ; push remainder (last digit) and replace old value with quotient
      cmp r10, 0
      jne log_int_loop

    ; write " eliminates "
    mov rcx, 12
    log_2_loop:
      lea rbx, [rel log_str_2]
      mov al, byte [rbx+rcx]
      dec rsp
      mov [rsp], al
      dec rcx
      jne log_2_loop

    ; write GUESS (rdi - guess in the form 00 00 00 00 00 07 04 03)
    mov rcx, 5
    log_guess_loop:
      add dil, 0x41
      dec rsp
      mov [rsp], dil ; push letter + 0x41 (letter 'A')
      shr rdi, 8 ; drop last letter
      
      dec rcx
      jne log_guess_loop
    
    ; write "guess "
    mov rcx, 6
    log_1_loop:
      lea rbx, [rel log_str_1]
      mov al, byte [rbx+rcx]
      dec rsp
      mov [rsp], al
      dec rcx
      jne log_1_loop

    mov rdi, rdx ; length of string
    mov rsi, rsp ; address of string to print is at rsp (not aligned)

    add rdx, 0b0000000000000000000000000000000000000000000000000000000000001111
    and rdx, 0b1111111111111111111111111111111111111111111111111111111111110000 ; round up to nearest 16
    mov rsp, r15
    sub rsp, rdx ; ensure 16-byte aligned RSP
    
    call win64_print

    mov rsp, r15 ; revive old rsp

    inc r12d
    cmp r12d, 14855
    jne for_PG
  
  ; Set up arguments for exit function
  xor rdi, rdi
  call win64_exit

; rdi - guess in the form 00 00 00 00 00 07 04 03
; rsi - secret in the form 00 00 00 00 00 07 04 03
; Return: r8 - colors in the form 00 00 00 01 02 00 02 01
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
    jne .skip

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
; output: one of xmm0, xmm1, xmm2 will be updated (via xor with a mask)
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
  pxor xmm0, xmm3
  ret
  .x0_right:
  sub rcx, 64
  shr rbx, cl
  pinsrq xmm3, rbx, 0
  pxor xmm0, xmm3
  ret

  .x1:
  cmp rcx, 191
  ja .x1_right
  .x1_left:
  sub rcx, 128
  shr rbx, cl
  pinsrq xmm3, rbx, 1
  pxor xmm1, xmm3
  ret
  .x1_right:
  sub rcx, 192
  shr rbx, cl
  pinsrq xmm3, rbx, 0
  pxor xmm1, xmm3
  ret
  
  .x2_left:
  sub rcx, 256
  shr rbx, cl
  pinsrq xmm3, rbx, 1
  pxor xmm2, xmm3
  ret
  
  .finish:
  

; write a sequence of bits into the xmm0-xmm2 bitmap
; rbx: index of leftmost bit (0-285)
; rcx: index of rightmost bit (0-285)
; modifies: rbx, rcx, r11, r14, r15, xmm0, xmm1, xmm2, xmm3
; output: xmm0, xmm1, xmm2 will be updated (via xor with a mask)
write_raw_bit_sequence:
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

  ret

  .do_it:
    push r11 ; end me
    push r14 ; it pains me to do this

    shl r11, 6 ; get base index
    sub rbx, r11
    sub rcx, r11 ; localize rbx and rcx indexes to the segment
    shr r11, 6 ; revert change to r11

    ; rcx is now a temp var used for shifting math (original MOVED to r15)
    mov r15, rcx
    mov r14, 1 ; init r14: bitmap to write into xmm3
    pxor xmm3, xmm3 ; init xmm3: actual bitmap for XORing
    sub rcx, rbx
    add rcx, 1
    shl r14, cl
    sub r14, 1 ; (1u64 << (right-left+1)) - 1)
    mov rcx, 127
    sub rcx, r15
    shl r14, cl
    ; r11 is the segment we want to write to (0-4)
    cmp r11, 3
    ja .x2_left
    je .x1_right
    cmp r11, 1
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
      pop r14
      pop r11
      ret

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

section .bss
  ; each word is 8 bytes (left 3 are 0, right 5 are u8 letters)
  ; 14855 words * 8 = 118840 bytes
  words_encoded resb 118840
  ; each bitmap needs to store 26*11 bits via 3 XMM registers. (16*3 = 48 bytes)
  ; there are 14855 bitmaps. 14855*48 = 713040
  alignb 16 ; yay! this works. now ptest doesnt give an exception.
  cached_bitmaps: resb 713040