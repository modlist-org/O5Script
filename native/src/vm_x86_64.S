.intel_syntax noprefix
.text

# Macro for fast PIC direct dispatch
.macro DISPATCH_NEXT
    movzx eax, byte ptr [r12 + 16]
    add r12, 16
    movsxd rax, dword ptr [r9 + rax*4]
    add rax, r9
    jmp rax
.endm

.macro DISPATCH_CUR
    movzx eax, byte ptr [r12]
    movsxd rax, dword ptr [r9 + rax*4]
    add rax, r9
    jmp rax
.endm

.globl o5s_vm_exec_x86_64
.type o5s_vm_exec_x86_64, @function
o5s_vm_exec_x86_64:
    # Prototype:
    # i32 o5s_vm_exec_x86_64(
    #     Prog* prog,            // rdi
    #     size_t entry_ip,       // rsi
    #     const double* host_vars,// rdx
    #     size_t host_count,     // rcx
    #     O5Result* out_res      // r8
    # )
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    # 16-byte stack alignment:
    # 5 callee pushes (40) + rbp (8) + ret (8) = 56.
    # 56 + 8 = 64 (0 mod 16).
    sub rsp, 65544

    # Save arguments in stable rbp slots (below callee-saved registers rbp-40):
    mov [rbp - 48], rdi          # [rbp - 48] = prog
    mov r15, [rdi]               # r15 = prog.ops.ptr (permanent fast register)
    mov [rbp - 88], rdx          # [rbp - 88] = host_vars
    mov [rbp - 80], r8           # [rbp - 80] = out_res
    mov [rbp - 56], rcx          # [rbp - 56] = host_count
    lea r14, [rbp - 2048]        # r14 = call stack base
    mov r13, r14                 # r13 = call stack pointer (grows upwards)

    # Zero out locals [rsp .. rsp + 16384]
    lea rdi, [rsp]
    xor eax, eax
    mov ecx, 2048
    rep stosq

    # r12 = current Op ptr = prog.ops.ptr + entry_ip * 16
    shl rsi, 4
    lea r12, [r15 + rsi]

    mov rbx, rsp                 # rbx = frame pointer (rsp + frame_offset)
    xor r10, r10                 # r10 = 0 (eval_stack sp in bytes)

    lea r11, [rsp + 32768]       # r11 = eval_stack base
    lea r9, [rip + o5s_dispatch_table]

    # Initial dispatch
    DISPATCH_CUR

# ---------------------------------------------------------------------------
# Opcode Handlers
# ---------------------------------------------------------------------------

.p2align 4
op_nop:
    DISPATCH_NEXT

.p2align 4
op_push_num:
    mov rax, [r12 + 8]
    mov [r11 + r10], rax
    mov dword ptr [r11 + r10 + 20], 0
    add r10, 24
    DISPATCH_NEXT

.p2align 4
op_push_0:
    xor eax, eax
    mov [r11 + r10], rax
    mov dword ptr [r11 + r10 + 20], 0
    add r10, 24
    DISPATCH_NEXT

.p2align 4
op_push_1:
    mov rax, 0x3ff0000000000000
    mov [r11 + r10], rax
    mov dword ptr [r11 + r10 + 20], 0
    add r10, 24
    DISPATCH_NEXT

.p2align 4
op_push_str:
    mov eax, dword ptr [r12 + 8]      # offset
    mov edx, dword ptr [r12 + 12]     # len
    mov rdi, [rbp - 48]               # prog
    mov rsi, [rdi + 16]               # string_pool.ptr
    add rsi, rax                      # str_ptr
    xor eax, eax
    mov [r11 + r10], rax              # num = 0.0
    mov [r11 + r10 + 8], rsi          # str_ptr
    mov [r11 + r10 + 16], edx         # str_len
    mov byte ptr [r11 + r10 + 20], 1  # val_type = str
    add r10, 24
    DISPATCH_NEXT

.p2align 4
op_pop:
    test r10, r10
    jz 1f
    sub r10, 24
1:
    DISPATCH_NEXT

.p2align 4
op_dup:
    mov rax, [r11 + r10 - 24]
    mov [r11 + r10], rax
    mov rax, [r11 + r10 - 16]
    mov [r11 + r10 + 8], rax
    mov rax, [r11 + r10 - 8]
    mov [r11 + r10 + 16], rax
    add r10, 24
    DISPATCH_NEXT

.p2align 4
op_load_local:
    mov rax, [r12 + 8]
    lea rax, [rax + rax*2]
    lea rcx, [rbx + rax*8]
    mov rax, [rcx]
    mov [r11 + r10], rax
    mov rax, [rcx + 8]
    mov [r11 + r10 + 8], rax
    mov rax, [rcx + 16]
    mov [r11 + r10 + 16], rax
    add r10, 24
    DISPATCH_NEXT

.p2align 4
op_store_local:
    mov rax, [r12 + 8]
    lea rdx, [rax + rax*2]
    lea rcx, [rbx + rdx*8]
    cmp byte ptr [r12 + 16], 7        # is next op load_local?
    jne .Lstore_normal
    cmp [r12 + 24], rax               # same slot?
    jne .Lstore_normal

    # Keep on stack! Copy to local and skip load_local:
    mov rax, [r11 + r10 - 24]
    mov [rcx], rax
    mov rax, [r11 + r10 - 16]
    mov [rcx + 8], rax
    mov rax, [r11 + r10 - 8]
    mov [rcx + 16], rax
    add r12, 16                       # skip load_local
    DISPATCH_NEXT

.Lstore_normal:
    sub r10, 24
    mov rax, [r11 + r10]
    mov [rcx], rax
    mov rax, [r11 + r10 + 8]
    mov [rcx + 8], rax
    mov rax, [r11 + r10 + 16]
    mov [rcx + 16], rax
    DISPATCH_NEXT

.p2align 4
op_load_state:
    mov rax, [r12 + 8]
    lea rax, [rax + rax*2]
    shl rax, 3
    mov rdi, [rbp - 48]          # prog
    mov rsi, [rdi + 80]          # prog.state_slots.ptr
    add rsi, rax
    mov rax, [rsi]
    mov [r11 + r10], rax
    mov rax, [rsi + 8]
    mov [r11 + r10 + 8], rax
    mov rax, [rsi + 16]
    mov [r11 + r10 + 16], rax
    add r10, 24
    DISPATCH_NEXT

.p2align 4
op_store_state:
    sub r10, 24
    mov rax, [r12 + 8]
    lea rax, [rax + rax*2]
    shl rax, 3
    mov rdi, [rbp - 48]          # prog
    mov rsi, [rdi + 80]          # prog.state_slots.ptr
    add rsi, rax
    mov rax, [r11 + r10]
    mov [rsi], rax
    mov rax, [r11 + r10 + 8]
    mov [rsi + 8], rax
    mov rax, [r11 + r10 + 16]
    mov [rsi + 16], rax
    DISPATCH_NEXT

.p2align 4
op_load_host:
    mov rax, [r12 + 8]
    cmp rax, [rbp - 56]
    jae 1f
    mov rdx, [rbp - 88]
    movsd xmm0, [rdx + rax*8]
    jmp 2f
1:
    xorpd xmm0, xmm0
2:
    movsd [r11 + r10], xmm0
    mov dword ptr [r11 + r10 + 20], 0
    add r10, 24
    DISPATCH_NEXT

.p2align 4
op_check_bounds:
    movsd xmm0, [r11 + r10 - 24]
    cvttsd2si rax, xmm0
    test rax, rax
    js .Lbounds_err
    cmp rax, [r12 + 8]
    jge .Lbounds_err
    cvtsi2sd xmm1, rax
    ucomisd xmm0, xmm1
    jne .Lbounds_err
    DISPATCH_NEXT
.Lbounds_err:
    mov eax, -6                  # OutOfBounds
    add rsp, 65544
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.p2align 4
op_load_local_elem:
    cvttsd2si rax, [r11 + r10 - 24]
    add rax, [r12 + 8]
    lea rax, [rax + rax*2]
    lea rcx, [rbx + rax*8]

    cmp byte ptr [r12 + 16], 8         # is next op store_local?
    jne .Lload_elem_normal

    # Direct copy from [rcx] to locals[dest]!
    sub r10, 24                        # pop idx from stack
    mov rdx, [r12 + 24]                # dest_slot
    lea rdx, [rdx + rdx*2]
    lea rdx, [rbx + rdx*8]             # rdx = pointer to locals[dest]

    mov rax, [rcx]
    mov [rdx], rax
    mov rax, [rcx + 8]
    mov [rdx + 8], rax
    mov rax, [rcx + 16]
    mov [rdx + 16], rax
    add r12, 16                        # skip store_local
    DISPATCH_NEXT

.Lload_elem_normal:
    mov rax, [rcx]
    mov [r11 + r10 - 24], rax
    mov rax, [rcx + 8]
    mov [r11 + r10 - 16], rax
    mov rax, [rcx + 16]
    mov [r11 + r10 - 8], rax
    DISPATCH_NEXT

.p2align 4
op_store_local_elem:
    cvttsd2si rax, [r11 + r10 - 48]
    add rax, [r12 + 8]
    lea rax, [rax + rax*2]
    lea rcx, [rbx + rax*8]
    mov rax, [r11 + r10 - 24]
    mov [rcx], rax
    mov rax, [r11 + r10 - 16]
    mov [rcx + 8], rax
    mov rax, [r11 + r10 - 8]
    mov [rcx + 16], rax
    sub r10, 48
    DISPATCH_NEXT

.p2align 4
op_load_state_elem:
    cvttsd2si rax, [r11 + r10 - 24]
    add rax, [r12 + 8]
    lea rax, [rax + rax*2]
    shl rax, 3
    mov rdi, [rbp - 48]
    mov rsi, [rdi + 80]
    add rsi, rax
    mov rax, [rsi]
    mov [r11 + r10 - 24], rax
    mov rax, [rsi + 8]
    mov [r11 + r10 - 16], rax
    mov rax, [rsi + 16]
    mov [r11 + r10 - 8], rax
    DISPATCH_NEXT

.p2align 4
op_store_state_elem:
    cvttsd2si rax, [r11 + r10 - 48]
    add rax, [r12 + 8]
    lea rax, [rax + rax*2]
    shl rax, 3
    mov rdi, [rbp - 48]
    mov rsi, [rdi + 80]
    add rsi, rax
    mov rax, [r11 + r10 - 24]
    mov [rsi], rax
    mov rax, [r11 + r10 - 16]
    mov [rsi + 8], rax
    mov rax, [r11 + r10 - 8]
    mov [rsi + 16], rax
    sub r10, 48
    DISPATCH_NEXT

.p2align 4
op_add:
    sub r10, 24
    cmp byte ptr [r11 + r10 - 4], 1
    je .Lasm_str_concat
    cmp byte ptr [r11 + r10 + 20], 1
    je .Lasm_str_concat
    movsd xmm0, [r11 + r10 - 24]
    addsd xmm0, [r11 + r10]
    movsd [r11 + r10 - 24], xmm0
    DISPATCH_NEXT
.Lasm_str_concat:
    lea rdi, [r11 + r10 - 24]
    lea rsi, [r11 + r10]
    mov [rbp - 72], r10
    call o5s_asm_str_add
    mov r10, [rbp - 72]
    lea r11, [rsp + 32768]
    lea r9, [rip + o5s_dispatch_table]
    DISPATCH_NEXT

.p2align 4
op_sub:
    sub r10, 24
    movsd xmm0, [r11 + r10 - 24]
    subsd xmm0, [r11 + r10]
    movsd [r11 + r10 - 24], xmm0
    DISPATCH_NEXT

.p2align 4
op_mul:
    sub r10, 24
    movsd xmm0, [r11 + r10 - 24]
    mulsd xmm0, [r11 + r10]
    movsd [r11 + r10 - 24], xmm0
    DISPATCH_NEXT

.p2align 4
op_div:
    sub r10, 24
    movsd xmm0, [r11 + r10 - 24]
    divsd xmm0, [r11 + r10]
    movsd [r11 + r10 - 24], xmm0
    DISPATCH_NEXT

.p2align 4
op_mod:
    sub r10, 24
    movsd xmm0, [r11 + r10 - 24]
    movsd xmm1, [r11 + r10]
    mov [rbp - 72], r10
    call fmod
    mov r10, [rbp - 72]
    lea r11, [rsp + 32768]
    lea r9, [rip + o5s_dispatch_table]
    movsd [r11 + r10 - 24], xmm0
    DISPATCH_NEXT

.p2align 4
op_neg:
    movsd xmm0, [r11 + r10 - 24]
    xorpd xmm1, xmm1
    subsd xmm1, xmm0
    movsd [r11 + r10 - 24], xmm1
    DISPATCH_NEXT

.p2align 4
op_bit_and:
    sub r10, 24
    cvttsd2si rax, [r11 + r10 - 24]
    cvttsd2si rcx, [r11 + r10]
    and rax, rcx
    cvtsi2sd xmm0, rax
    movsd [r11 + r10 - 24], xmm0
    DISPATCH_NEXT

.p2align 4
op_bit_or:
    sub r10, 24
    cvttsd2si rax, [r11 + r10 - 24]
    cvttsd2si rcx, [r11 + r10]
    or rax, rcx
    cvtsi2sd xmm0, rax
    movsd [r11 + r10 - 24], xmm0
    DISPATCH_NEXT

.p2align 4
op_bit_xor:
    sub r10, 24
    cvttsd2si rax, [r11 + r10 - 24]
    cvttsd2si rcx, [r11 + r10]
    xor rax, rcx
    cvtsi2sd xmm0, rax
    movsd [r11 + r10 - 24], xmm0
    DISPATCH_NEXT

.p2align 4
op_bit_not:
    cvttsd2si rax, [r11 + r10 - 24]
    not rax
    cvtsi2sd xmm0, rax
    movsd [r11 + r10 - 24], xmm0
    DISPATCH_NEXT

.p2align 4
op_shl:
    sub r10, 24
    cvttsd2si rax, [r11 + r10 - 24]
    cvttsd2si rcx, [r11 + r10]
    shl rax, cl
    cvtsi2sd xmm0, rax
    movsd [r11 + r10 - 24], xmm0
    DISPATCH_NEXT

.p2align 4
op_shr:
    sub r10, 24
    cvttsd2si rax, [r11 + r10 - 24]
    cvttsd2si rcx, [r11 + r10]
    shr rax, cl
    cvtsi2sd xmm0, rax
    movsd [r11 + r10 - 24], xmm0
    DISPATCH_NEXT

.p2align 4
op_eq:
    sub r10, 24
    movsd xmm0, [r11 + r10 - 24]
    movsd xmm1, [r11 + r10]
    cmp byte ptr [r12 + 16], 37      # is next op jmp_if_zero?
    je .Leq_fuse_jmp_zero
    ucomisd xmm0, xmm1
    sete al
    setnp cl
    and al, cl
    movzx eax, al
    cvtsi2sd xmm0, eax
    movsd [r11 + r10 - 24], xmm0
    mov dword ptr [r11 + r10 - 4], 0
    DISPATCH_NEXT
.Leq_fuse_jmp_zero:
    sub r10, 24
    ucomisd xmm0, xmm1
    jne .Leq_take_jmp
    jp .Leq_take_jmp
    add r12, 16
    DISPATCH_NEXT
.Leq_take_jmp:
    mov rax, [r12 + 24]
    shl rax, 4
    lea r12, [r15 + rax]
    DISPATCH_CUR

.p2align 4
op_ne:
    sub r10, 24
    movsd xmm0, [r11 + r10 - 24]
    movsd xmm1, [r11 + r10]
    cmp byte ptr [r12 + 16], 37      # is next op jmp_if_zero?
    je .Lne_fuse_jmp_zero
    ucomisd xmm0, xmm1
    setne al
    setp cl
    or al, cl
    movzx eax, al
    cvtsi2sd xmm0, eax
    movsd [r11 + r10 - 24], xmm0
    mov dword ptr [r11 + r10 - 4], 0
    DISPATCH_NEXT
.Lne_fuse_jmp_zero:
    sub r10, 24
    ucomisd xmm0, xmm1
    jp .Lne_take_no_jmp
    je .Lne_take_jmp
.Lne_take_no_jmp:
    add r12, 16
    DISPATCH_NEXT
.Lne_take_jmp:
    mov rax, [r12 + 24]
    shl rax, 4
    lea r12, [r15 + rax]
    DISPATCH_CUR

.p2align 4
op_lt:
    sub r10, 24
    movsd xmm0, [r11 + r10 - 24]
    movsd xmm1, [r11 + r10]
    cmp byte ptr [r12 + 16], 37      # is next op jmp_if_zero?
    je .Llt_fuse_jmp_zero
    ucomisd xmm0, xmm1
    setb al
    movzx eax, al
    cvtsi2sd xmm0, eax
    movsd [r11 + r10 - 24], xmm0
    mov dword ptr [r11 + r10 - 4], 0
    DISPATCH_NEXT
.Llt_fuse_jmp_zero:
    sub r10, 24
    ucomisd xmm0, xmm1
    jae .Llt_take_jmp
    jp .Llt_take_jmp
    add r12, 16
    DISPATCH_NEXT
.Llt_take_jmp:
    mov rax, [r12 + 24]
    shl rax, 4
    lea r12, [r15 + rax]
    DISPATCH_CUR

.p2align 4
op_le:
    sub r10, 24
    movsd xmm0, [r11 + r10 - 24]
    movsd xmm1, [r11 + r10]
    cmp byte ptr [r12 + 16], 37      # is next op jmp_if_zero?
    je .Lle_fuse_jmp_zero
    ucomisd xmm0, xmm1
    setbe al
    movzx eax, al
    cvtsi2sd xmm0, eax
    movsd [r11 + r10 - 24], xmm0
    mov dword ptr [r11 + r10 - 4], 0
    DISPATCH_NEXT
.Lle_fuse_jmp_zero:
    sub r10, 24
    ucomisd xmm0, xmm1
    ja .Lle_take_jmp
    jp .Lle_take_jmp
    add r12, 16
    DISPATCH_NEXT
.Lle_take_jmp:
    mov rax, [r12 + 24]
    shl rax, 4
    lea r12, [r15 + rax]
    DISPATCH_CUR

.p2align 4
op_gt:
    sub r10, 24
    movsd xmm0, [r11 + r10 - 24]
    movsd xmm1, [r11 + r10]
    cmp byte ptr [r12 + 16], 37      # is next op jmp_if_zero?
    je .Lgt_fuse_jmp_zero
    ucomisd xmm0, xmm1
    seta al
    movzx eax, al
    cvtsi2sd xmm0, eax
    movsd [r11 + r10 - 24], xmm0
    mov dword ptr [r11 + r10 - 4], 0
    DISPATCH_NEXT
.Lgt_fuse_jmp_zero:
    sub r10, 24
    ucomisd xmm0, xmm1
    jbe .Lgt_take_jmp
    jp .Lgt_take_jmp
    add r12, 16
    DISPATCH_NEXT
.Lgt_take_jmp:
    mov rax, [r12 + 24]
    shl rax, 4
    lea r12, [r15 + rax]
    DISPATCH_CUR

.p2align 4
op_ge:
    sub r10, 24
    movsd xmm0, [r11 + r10 - 24]
    movsd xmm1, [r11 + r10]
    cmp byte ptr [r12 + 16], 37      # is next op jmp_if_zero?
    je .Lge_fuse_jmp_zero
    ucomisd xmm0, xmm1
    setae al
    movzx eax, al
    cvtsi2sd xmm0, eax
    movsd [r11 + r10 - 24], xmm0
    mov dword ptr [r11 + r10 - 4], 0
    DISPATCH_NEXT
.Lge_fuse_jmp_zero:
    sub r10, 24
    ucomisd xmm0, xmm1
    jb .Lge_take_jmp
    jp .Lge_take_jmp
    add r12, 16
    DISPATCH_NEXT
.Lge_take_jmp:
    mov rax, [r12 + 24]
    shl rax, 4
    lea r12, [r15 + rax]
    DISPATCH_CUR

.p2align 4
op_lnot:
    movsd xmm0, [r11 + r10 - 24]
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    sete al
    setp cl
    or al, cl
    movzx eax, al
    cvtsi2sd xmm0, eax
    movsd [r11 + r10 - 24], xmm0
    DISPATCH_NEXT

.p2align 4
op_jmp:
    mov rax, [r12 + 8]
    shl rax, 4
    lea r12, [r15 + rax]
    DISPATCH_CUR

.p2align 4
op_jmp_if_zero:
    sub r10, 24
    movsd xmm0, [r11 + r10]
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    jp 1f
    je 1f
    DISPATCH_NEXT
1:
    mov rax, [r12 + 8]
    shl rax, 4
    lea r12, [r15 + rax]
    DISPATCH_CUR

.p2align 4
op_jmp_if_nonzero:
    sub r10, 24
    movsd xmm0, [r11 + r10]
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    jp 2f
    jne 1f
2:
    DISPATCH_NEXT
1:
    mov rax, [r12 + 8]
    shl rax, 4
    lea r12, [r15 + rax]
    DISPATCH_CUR

.p2align 4
op_call_builtin:
    movzx eax, byte ptr [r12 + 8]      # builtin_id
    cmp al, 7                          # Builtin.sqrt = 7
    jne 1f
    sqrtsd xmm0, [r11 + r10 - 24]
    movsd [r11 + r10 - 24], xmm0
    DISPATCH_NEXT
1:
    cmp al, 8                          # Builtin.abs = 8
    jne 2f
    mov rax, 0x7fffffffffffffff
    and [r11 + r10 - 24], rax
    DISPATCH_NEXT
2:
    cmp al, 9                          # Builtin.floor = 9
    jne 3f
    roundsd xmm0, [r11 + r10 - 24], 1
    movsd [r11 + r10 - 24], xmm0
    DISPATCH_NEXT
3:
    cmp al, 10                         # Builtin.ceil = 10
    jne 4f
    roundsd xmm0, [r11 + r10 - 24], 2
    movsd [r11 + r10 - 24], xmm0
    DISPATCH_NEXT
4:
    cmp al, 11                         # Builtin.round = 11
    jne 5f
    roundsd xmm0, [r11 + r10 - 24], 0
    movsd [r11 + r10 - 24], xmm0
    DISPATCH_NEXT
5:
    test al, al                        # Builtin.sin = 0
    jne 6f
    movsd xmm0, [r11 + r10 - 24]
    mov [rbp - 72], r10
    call sin
    mov r10, [rbp - 72]
    lea r11, [rsp + 32768]
    lea r9, [rip + o5s_dispatch_table]
    movsd [r11 + r10 - 24], xmm0
    DISPATCH_NEXT
6:
    cmp al, 1                          # Builtin.cos = 1
    jne 7f
    movsd xmm0, [r11 + r10 - 24]
    mov [rbp - 72], r10
    call cos
    mov r10, [rbp - 72]
    lea r11, [rsp + 32768]
    lea r9, [rip + o5s_dispatch_table]
    movsd [r11 + r10 - 24], xmm0
    DISPATCH_NEXT
7:
    mov rdi, [r12 + 8]
    lea rsi, [r11 + r10]
    mov [rbp - 72], r10
    call o5s_asm_builtin_call
    mov r10, [rbp - 72]
    sub r10, rax
    lea r11, [rsp + 32768]
    lea r9, [rip + o5s_dispatch_table]
    DISPATCH_NEXT

.p2align 4
op_call:
    mov eax, dword ptr [r12 + 8]      # target_ip
    mov edx, dword ptr [r12 + 12]     # precomputed frame_shift * 24 in bytes

    lea rsi, [r12 + 16]              # return ip
    mov [r13], rsi                   # save ret_ip
    mov [r13 + 8], rbx               # save prev_fp
    add r13, 16                      # push to call stack

    add rbx, rdx                     # shift fp directly

    shl rax, 4
    lea r12, [r15 + rax]
    DISPATCH_CUR

.p2align 4
op_ret:
    cmp r13, r14
    jbe op_halt
    sub r13, 16
    mov r12, [r13]                   # restore ret_ip
    mov rbx, [r13 + 8]               # restore prev_fp
    DISPATCH_CUR

.p2align 4
op_halt:
    mov r13, [rbp - 80]              # restore out_res
    test r10, r10
    jz 1f
    mov rax, [r11 + r10 - 24]
    mov [r13], rax
    mov rax, [r11 + r10 - 16]
    mov [r13 + 8], rax
    mov rax, [r11 + r10 - 8]
    mov [r13 + 16], rax
    jmp 2f
1:
    xor eax, eax
    mov [r13], rax
    mov [r13 + 8], rax
    mov [r13 + 16], rax
2:
    xor eax, eax
    add rsp, 65544
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.p2align 4
op_loop_step:
    mov rax, [r12 + 8]                 # packed_arg
    movzx edx, ax                      # edx = vslot
    shr rax, 16
    movzx ecx, ax                      # ecx = limit_slot
    shr rax, 16                        # rax = target_ip

    # Check if target_ip is immediately preceding and is op_add_local (opcode 44)
    mov rsi, rax
    shl rsi, 4
    add rsi, r15                       # rsi = pointer to target Op
    lea rdi, [rsi + 16]
    cmp rdi, r12                       # does loop body consist solely of target Op?
    jne .Lloop_step_normal

    cmp byte ptr [rsi], 44             # is target Op opcode 44 (add_local)?
    jne .Lloop_step_normal

    # FAST TIGHT ACCUMULATOR LOOP!
    mov r8, [rsi + 8]
    movzx edi, r8w                     # edi = dest_slot
    shr r8, 16
    movzx esi, r8w                     # esi = src_slot
    cmp esi, edx                       # is src_slot == vslot (adding the loop counter)?
    jne .Lloop_step_normal

    # Match! Tight numeric accumulator loop:
    lea rdi, [rdi + rdi*2]
    lea rdx, [rdx + rdx*2]
    lea rcx, [rcx + rcx*2]

    movsd xmm0, [rbx + rdx*8]          # counter (i)
    movsd xmm1, [rbx + rcx*8]          # limit
    movsd xmm2, [rbx + rdi*8]          # sum (s)

    # First iteration increment that this loop_step was about to do:
    addsd xmm0, [rip + .Lconst_one]
    ucomisd xmm0, xmm1
    jae .Ltight_done
    jp .Ltight_done

    movsd xmm3, xmm1
    subsd xmm3, xmm0
    cvttsd2si rcx, xmm3                # rcx = remaining trip count
    test rcx, rcx
    jle .Ltight_done

    mov r8, rcx
    and r8, 3                          # r8 = remainder
    shr rcx, 2                         # rcx = 4-batch count
    test rcx, rcx
    jz .Ltight_rem

.p2align 4
.Ltight_loop_4:
    addsd xmm2, xmm0
    addsd xmm0, [rip + .Lconst_one]
    addsd xmm2, xmm0
    addsd xmm0, [rip + .Lconst_one]
    addsd xmm2, xmm0
    addsd xmm0, [rip + .Lconst_one]
    addsd xmm2, xmm0
    addsd xmm0, [rip + .Lconst_one]
    dec rcx
    jnz .Ltight_loop_4

.Ltight_rem:
    test r8, r8
    jz .Ltight_done
.Ltight_scalar:
    addsd xmm2, xmm0
    addsd xmm0, [rip + .Lconst_one]
    dec r8
    jnz .Ltight_scalar

.Ltight_done:
    movsd [rbx + rdx*8], xmm0          # store final counter
    movsd [rbx + rdi*8], xmm2          # store final sum
    DISPATCH_NEXT

.Lloop_step_normal:
    # Check if target_ip is an array accumulator loop (4 opcodes: load_local, load_local_elem, store_local, add_local)
    lea rdi, [rsi + 64]
    cmp rdi, r12
    jne .Lloop_step_fallback

    cmp byte ptr [rsi], 7              # load_local
    jne .Lloop_step_fallback
    cmp byte ptr [rsi + 16], 13        # load_local_elem
    jne .Lloop_step_fallback
    cmp byte ptr [rsi + 32], 8         # store_local
    jne .Lloop_step_fallback
    cmp byte ptr [rsi + 48], 44        # add_local
    jne .Lloop_step_fallback

    # Verify operands:
    cmp [rsi + 8], rdx                 # load_local slot == idx_slot (edx)
    jne .Lloop_step_fallback

    mov r8, [rsi + 48 + 8]             # add_local arg
    movzx edi, r8w                     # dest_s
    shr r8, 16
    movzx r8d, r8w                     # src_v
    cmp [rsi + 32 + 8], r8             # store_local slot == src_v
    jne .Lloop_step_fallback

    # Match! Fast tight array accumulation loop:
    mov r14, [rsi + 16 + 8]            # a_base

    # Convert counter (edx) and limit (ecx) to int:
    lea r8, [rdx + rdx*2]
    cvttsd2si r8, [rbx + r8*8]         # r8 = current counter int
    lea r9, [rcx + rcx*2]
    cvttsd2si rcx, [rbx + r9*8]        # rcx = limit int

    lea rdi, [rdi + rdi*2]
    movsd xmm2, [rbx + rdi*8]          # xmm2 = sum (s)

    # First iteration step:
    inc r8
    cmp r8, rcx
    jae .Ltarry_done

.p2align 4
.Ltarry_step:
    lea rax, [r14 + r8]
    lea rax, [rax + rax*2]
    addsd xmm2, [rbx + rax*8]          # s += a[counter].num
    inc r8
    cmp r8, rcx
    jb .Ltarry_step

.Ltarry_done:
    cvtsi2sd xmm0, r8
    lea rdx, [rdx + rdx*2]
    movsd [rbx + rdx*8], xmm0          # store final counter
    movsd [rbx + rdi*8], xmm2          # store final sum
    lea r9, [rip + o5s_dispatch_table] # restore r9 dispatch table!
    DISPATCH_NEXT

.Lloop_step_fallback:
    lea rdx, [rdx + rdx*2]             # rdx = vslot * 3
    lea rcx, [rcx + rcx*2]             # rcx = limit_slot * 3

    movsd xmm0, [rbx + rdx*8]          # counter
    addsd xmm0, [rip + .Lconst_one]    # counter += 1.0
    movsd [rbx + rdx*8], xmm0          # store updated counter

    ucomisd xmm0, [rbx + rcx*8]        # counter < limit
    jae .Lloop_step_exit
    jp .Lloop_step_exit

    shl rax, 4
    lea r12, [r15 + rax]               # loop_body_ip
    DISPATCH_CUR

.Lloop_step_exit:
    DISPATCH_NEXT

.p2align 4
op_add_local:
    mov rax, [r12 + 8]                 # packed_arg
    movzx edx, ax                      # edx = dest_slot
    shr rax, 16
    movzx ecx, ax                      # ecx = src_slot

    lea rdx, [rdx + rdx*2]             # rdx = dest_slot * 3
    lea rcx, [rcx + rcx*2]             # rcx = src_slot * 3

    movsd xmm0, [rbx + rdx*8]
    addsd xmm0, [rbx + rcx*8]
    movsd [rbx + rdx*8], xmm0
    DISPATCH_NEXT

# ---------------------------------------------------------------------------
# Direct Relative Dispatch Table (45 opcodes, 4 bytes each, PIC-safe)
# ---------------------------------------------------------------------------
.section .rodata
.p2align 3
.Lconst_one:
    .double 1.0
.Lconst_four:
    .double 4.0

.p2align 3
o5s_dispatch_table:
    .long op_nop - o5s_dispatch_table               # 0
    .long op_push_num - o5s_dispatch_table           # 1
    .long op_push_0 - o5s_dispatch_table             # 2
    .long op_push_1 - o5s_dispatch_table             # 3
    .long op_push_str - o5s_dispatch_table           # 4
    .long op_pop - o5s_dispatch_table                # 5
    .long op_dup - o5s_dispatch_table                # 6
    .long op_load_local - o5s_dispatch_table         # 7
    .long op_store_local - o5s_dispatch_table        # 8
    .long op_load_state - o5s_dispatch_table         # 9
    .long op_store_state - o5s_dispatch_table        # 10
    .long op_load_host - o5s_dispatch_table          # 11
    .long op_check_bounds - o5s_dispatch_table       # 12
    .long op_load_local_elem - o5s_dispatch_table    # 13
    .long op_store_local_elem - o5s_dispatch_table   # 14
    .long op_load_state_elem - o5s_dispatch_table    # 15
    .long op_store_state_elem - o5s_dispatch_table   # 16
    .long op_add - o5s_dispatch_table                # 17
    .long op_sub - o5s_dispatch_table                # 18
    .long op_mul - o5s_dispatch_table                # 19
    .long op_div - o5s_dispatch_table                # 20
    .long op_mod - o5s_dispatch_table                # 21
    .long op_neg - o5s_dispatch_table                # 22
    .long op_bit_and - o5s_dispatch_table            # 23
    .long op_bit_or - o5s_dispatch_table             # 24
    .long op_bit_xor - o5s_dispatch_table            # 25
    .long op_bit_not - o5s_dispatch_table            # 26
    .long op_shl - o5s_dispatch_table                # 27
    .long op_shr - o5s_dispatch_table                # 28
    .long op_eq - o5s_dispatch_table                 # 29
    .long op_ne - o5s_dispatch_table                 # 30
    .long op_lt - o5s_dispatch_table                 # 31
    .long op_le - o5s_dispatch_table                 # 32
    .long op_gt - o5s_dispatch_table                 # 33
    .long op_ge - o5s_dispatch_table                 # 34
    .long op_lnot - o5s_dispatch_table               # 35
    .long op_jmp - o5s_dispatch_table                # 36
    .long op_jmp_if_zero - o5s_dispatch_table        # 37
    .long op_jmp_if_nonzero - o5s_dispatch_table     # 38
    .long op_call_builtin - o5s_dispatch_table       # 39
    .long op_call - o5s_dispatch_table               # 40
    .long op_ret - o5s_dispatch_table                # 41
    .long op_halt - o5s_dispatch_table               # 42
    .long op_loop_step - o5s_dispatch_table          # 43
    .long op_add_local - o5s_dispatch_table          # 44
