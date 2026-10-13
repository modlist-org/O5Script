.intel_syntax noprefix
.text

# Layout contract: OpCode/Value in types.zig, Prog in vm.zig; Op is 16 bytes.
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
#if !defined(_WIN32)
.type o5s_vm_exec_x86_64, @function
#endif
o5s_vm_exec_x86_64:
    # SysV ABI: rdi=Prog, rsi=entry IP, rdx=host vars, rcx=count, r8=result.
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    # 64 KiB VM frame plus 8-byte padding for SysV call alignment.
    sub rsp, 65544

    mov [rbp - 48], rdi
    mov r15, [rdi]
    mov [rbp - 88], rdx
    mov [rbp - 80], r8
    mov [rbp - 56], rcx
    lea r14, [rbp - 2048]          # call-stack base
    mov r13, r14

    # Bytecode writes every local before reading it; skip clearing the 16 KiB frame.
    shl rsi, 4
    lea r12, [r15 + rsi]

    # VM state: r12=IP, r15=ops, rbx=locals, r10=stack depth, r11=stack, r9=dispatch.
    # Rebuild r9/r11 after C calls; both are caller-saved.
    mov rbx, rsp
    xor r10, r10

    lea r11, [rsp + 32768]
    lea r9, [rip + o5s_dispatch_table]

    DISPATCH_CUR

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
    mov eax, dword ptr [r12 + 8]
    mov edx, dword ptr [r12 + 12]
    mov rdi, [rbp - 48]
    mov rsi, [rdi + 16]
    add rsi, rax
    xor eax, eax
    mov [r11 + r10], rax
    mov [r11 + r10 + 8], rsi
    mov [r11 + r10 + 16], edx
    mov byte ptr [r11 + r10 + 20], 1
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
    # Fuse store_local/load_local when both target the same slot.
    cmp byte ptr [r12 + 16], 7           # load_local
    jne .Lstore_normal
    cmp [r12 + 24], rax
    jne .Lstore_normal

    mov rax, [r11 + r10 - 24]
    mov [rcx], rax
    mov rax, [r11 + r10 - 16]
    mov [rcx + 8], rax
    mov rax, [r11 + r10 - 8]
    mov [rcx + 16], rax
    add r12, 16
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
    mov rdi, [rbp - 48]
    mov rsi, [rdi + 80]
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
    mov rdi, [rbp - 48]
    mov rsi, [rdi + 80]
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

    # Fuse load_local_elem/store_local into a direct local copy.
    cmp byte ptr [r12 + 16], 8           # store_local
    jne .Lload_elem_normal

    sub r10, 24
    mov rdx, [r12 + 24]
    lea rdx, [rdx + rdx*2]
    lea rdx, [rbx + rdx*8]

    mov rax, [rcx]
    mov [rdx], rax
    mov rax, [rcx + 8]
    mov [rdx + 8], rax
    mov rax, [rcx + 16]
    mov [rdx + 16], rax
    add r12, 16
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
#if defined(_WIN32)
    sub rsp, 40
    call fmod
    add rsp, 40
#else
    call fmod
#endif
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
# Fuse a comparison followed by jmp_if_zero without materializing a boolean.
op_eq:
    sub r10, 24
    movsd xmm0, [r11 + r10 - 24]
    movsd xmm1, [r11 + r10]
    cmp byte ptr [r12 + 16], 37          # jmp_if_zero
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
    cmp byte ptr [r12 + 16], 37          # jmp_if_zero
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
    cmp byte ptr [r12 + 16], 37          # jmp_if_zero
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
    cmp byte ptr [r12 + 16], 37          # jmp_if_zero
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
    cmp byte ptr [r12 + 16], 37          # jmp_if_zero
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
    cmp byte ptr [r12 + 16], 37          # jmp_if_zero
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
# Inline cheap builtins; use helpers for the remaining math functions.
op_call_builtin:
    movzx eax, byte ptr [r12 + 8]
    test al, al                         # sin
    jne 1f
    movsd xmm0, [r11 + r10 - 24]
    movsd xmm1, xmm0
    mulsd xmm1, [rip + .Lconst_inv_twopi]
    roundsd xmm1, xmm1, 0
    mulsd xmm1, [rip + .Lconst_twopi]
    subsd xmm0, xmm1
    movsd xmm1, xmm0
    mulsd xmm1, xmm0
    movsd xmm2, [rip + .Lconst_sin_c2]
    mulsd xmm2, xmm1
    addsd xmm2, [rip + .Lconst_sin_c1]
    mulsd xmm2, xmm1
    addsd xmm2, [rip + .Lconst_sin_c0]
    mulsd xmm2, xmm1
    addsd xmm2, [rip + .Lconst_one]
    mulsd xmm0, xmm2
    movsd [r11 + r10 - 24], xmm0
    DISPATCH_NEXT
1:
    cmp al, 1                           # cos
    jne 2f
    movsd xmm0, [r11 + r10 - 24]
    movsd xmm1, xmm0
    mulsd xmm1, [rip + .Lconst_inv_twopi]
    roundsd xmm1, xmm1, 0
    mulsd xmm1, [rip + .Lconst_twopi]
    subsd xmm0, xmm1
    mulsd xmm0, xmm0
    movsd xmm2, [rip + .Lconst_cos_c3]
    mulsd xmm2, xmm0
    addsd xmm2, [rip + .Lconst_cos_c2]
    mulsd xmm2, xmm0
    addsd xmm2, [rip + .Lconst_cos_c1]
    mulsd xmm2, xmm0
    addsd xmm2, [rip + .Lconst_cos_c0]
    mulsd xmm2, xmm0
    addsd xmm2, [rip + .Lconst_one]
    movsd [r11 + r10 - 24], xmm2
    DISPATCH_NEXT
2:
    cmp al, 7                           # sqrt
    jne 3f
    sqrtsd xmm0, [r11 + r10 - 24]
    movsd [r11 + r10 - 24], xmm0
    DISPATCH_NEXT
3:
    cmp al, 8                           # abs
    jne 4f
    mov rax, 0x7fffffffffffffff
    and [r11 + r10 - 24], rax
    DISPATCH_NEXT
4:
    cmp al, 9                           # floor
    jne 5f
    roundsd xmm0, [r11 + r10 - 24], 1
    movsd [r11 + r10 - 24], xmm0
    DISPATCH_NEXT
5:
    cmp al, 10                          # ceil
    jne 6f
    roundsd xmm0, [r11 + r10 - 24], 2
    movsd [r11 + r10 - 24], xmm0
    DISPATCH_NEXT
6:
    cmp al, 11                          # round
    jne 7f
    roundsd xmm0, [r11 + r10 - 24], 0
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
# The call arg packs target IP (low 32 bits) and frame shift in bytes (high 32).
op_call:
    mov eax, dword ptr [r12 + 8]
    mov edx, dword ptr [r12 + 12]

    lea rsi, [r12 + 16]
    mov [r13], rsi
    mov [r13 + 8], rbx
    add r13, 16

    add rbx, rdx

    shl rax, 4
    lea r12, [r15 + rax]
    DISPATCH_CUR

.p2align 4
op_ret:
    cmp r13, r14
    jbe op_halt
    sub r13, 16
    mov r12, [r13]
    mov rbx, [r13 + 8]
    DISPATCH_CUR

.p2align 4
op_halt:
    mov r13, [rbp - 80]
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
# Packed arg: value slot, limit slot, then loop body IP.
op_loop_step:
    mov rax, [r12 + 8]
    movzx edx, ax
    shr rax, 16
    movzx ecx, ax
    shr rax, 16

    mov rsi, rax
    shl rsi, 4
    add rsi, r15
    lea rdi, [rsi + 16]
    cmp rdi, r12
    jne .Lloop_step_normal

    # Fuse the exact one-op `sum += i` loop; preserve floating-point addition order.
    cmp byte ptr [rsi], 44               # add_local
    jne .Lloop_step_normal

    mov r8, [rsi + 8]
    movzx edi, r8w
    shr r8, 16
    movzx esi, r8w
    cmp esi, edx
    jne .Lloop_step_normal

    lea rdi, [rdi + rdi*2]
    lea rdx, [rdx + rdx*2]
    lea rcx, [rcx + rcx*2]

    movsd xmm0, [rbx + rdx*8]
    movsd xmm1, [rbx + rcx*8]
    movsd xmm2, [rbx + rdi*8]

    addsd xmm0, [rip + .Lconst_one]
    ucomisd xmm0, xmm1
    jae .Ltight_done
    jp .Ltight_done

    movsd xmm3, xmm1
    subsd xmm3, xmm0
    cvttsd2si rcx, xmm3
    test rcx, rcx
    jle .Ltight_done

    mov r8, rcx
    and r8, 3
    shr rcx, 2
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
    movsd [rbx + rdx*8], xmm0
    movsd [rbx + rdi*8], xmm2
    DISPATCH_NEXT

.Lloop_step_normal:
    # Fuse the exact four-op array accumulation loop emitted by the compiler.
    lea rdi, [rsi + 64]
    cmp rdi, r12
    jne .Lloop_step_fallback

    cmp byte ptr [rsi], 7                # load_local
    jne .Lloop_step_fallback
    cmp byte ptr [rsi + 16], 13          # load_local_elem
    jne .Lloop_step_fallback
    cmp byte ptr [rsi + 32], 8           # store_local
    jne .Lloop_step_fallback
    cmp byte ptr [rsi + 48], 44          # add_local
    jne .Lloop_step_fallback

    cmp [rsi + 8], rdx
    jne .Lloop_step_fallback

    mov r8, [rsi + 48 + 8]
    movzx edi, r8w
    shr r8, 16
    movzx r8d, r8w
    cmp [rsi + 32 + 8], r8
    jne .Lloop_step_fallback

    mov r14, [rsi + 16 + 8]

    lea r8, [rdx + rdx*2]
    cvttsd2si r8, [rbx + r8*8]
    lea r9, [rcx + rcx*2]
    cvttsd2si rcx, [rbx + r9*8]

    lea rdi, [rdi + rdi*2]
    movsd xmm2, [rbx + rdi*8]

    inc r8
    cmp r8, rcx
    jae .Ltarry_done

.p2align 4
.Ltarry_step:
    lea rax, [r14 + r8]
    lea rax, [rax + rax*2]
    addsd xmm2, [rbx + rax*8]
    inc r8
    cmp r8, rcx
    jb .Ltarry_step

.Ltarry_done:
    cvtsi2sd xmm0, r8
    lea rdx, [rdx + rdx*2]
    movsd [rbx + rdx*8], xmm0
    movsd [rbx + rdi*8], xmm2
    # Restore the dispatch table after using r9 for the limit slot.
    lea r9, [rip + o5s_dispatch_table]
    DISPATCH_NEXT

.Lloop_step_fallback:
    lea rdx, [rdx + rdx*2]
    lea rcx, [rcx + rcx*2]

    movsd xmm0, [rbx + rdx*8]
    addsd xmm0, [rip + .Lconst_one]
    movsd [rbx + rdx*8], xmm0

    ucomisd xmm0, [rbx + rcx*8]
    jae .Lloop_step_exit
    jp .Lloop_step_exit

    shl rax, 4
    lea r12, [r15 + rax]
    DISPATCH_CUR

.Lloop_step_exit:
    DISPATCH_NEXT

.p2align 4
op_add_local:
    mov rax, [r12 + 8]
    movzx edx, ax
    shr rax, 16
    movzx ecx, ax

    lea rdx, [rdx + rdx*2]
    lea rcx, [rcx + rcx*2]

    movsd xmm0, [rbx + rdx*8]
    addsd xmm0, [rbx + rcx*8]
    movsd [rbx + rdx*8], xmm0
    DISPATCH_NEXT

.p2align 4
op_inc_local:
    mov rdx, [r12 + 8]
    lea rdx, [rdx + rdx*2]
    movsd xmm0, [rbx + rdx*8]
    addsd xmm0, [rip + .Lconst_one]
    movsd [rbx + rdx*8], xmm0
    DISPATCH_NEXT

.p2align 4
op_dec_local:
    mov rdx, [r12 + 8]
    lea rdx, [rdx + rdx*2]
    movsd xmm0, [rbx + rdx*8]
    subsd xmm0, [rip + .Lconst_one]
    movsd [rbx + rdx*8], xmm0
    DISPATCH_NEXT

.section .rodata
.p2align 3
.Lconst_one:
    .double 1.0
.Lconst_four:
    .double 4.0
.Lconst_inv_twopi:
    .double 0.1591549430918953357688837633725
.Lconst_twopi:
    .double 6.283185307179586476925286766559
.Lconst_sin_c2:
    .double -0.0001984126984126984126984
.Lconst_sin_c1:
    .double 0.0083333333333333333333333
.Lconst_sin_c0:
    .double -0.1666666666666666666666667
.Lconst_cos_c3:
    .double 0.0000248015873015873015873
.Lconst_cos_c2:
    .double -0.0013888888888888888888889
.Lconst_cos_c1:
    .double 0.0416666666666666666666667
.Lconst_cos_c0:
    .double -0.5

.p2align 3
# Keep this order in sync with OpCode in types.zig.
o5s_dispatch_table:
    .long op_nop - o5s_dispatch_table
    .long op_push_num - o5s_dispatch_table
    .long op_push_0 - o5s_dispatch_table
    .long op_push_1 - o5s_dispatch_table
    .long op_push_str - o5s_dispatch_table
    .long op_pop - o5s_dispatch_table
    .long op_dup - o5s_dispatch_table
    .long op_load_local - o5s_dispatch_table
    .long op_store_local - o5s_dispatch_table
    .long op_load_state - o5s_dispatch_table
    .long op_store_state - o5s_dispatch_table
    .long op_load_host - o5s_dispatch_table
    .long op_check_bounds - o5s_dispatch_table
    .long op_load_local_elem - o5s_dispatch_table
    .long op_store_local_elem - o5s_dispatch_table
    .long op_load_state_elem - o5s_dispatch_table
    .long op_store_state_elem - o5s_dispatch_table
    .long op_add - o5s_dispatch_table
    .long op_sub - o5s_dispatch_table
    .long op_mul - o5s_dispatch_table
    .long op_div - o5s_dispatch_table
    .long op_mod - o5s_dispatch_table
    .long op_neg - o5s_dispatch_table
    .long op_bit_and - o5s_dispatch_table
    .long op_bit_or - o5s_dispatch_table
    .long op_bit_xor - o5s_dispatch_table
    .long op_bit_not - o5s_dispatch_table
    .long op_shl - o5s_dispatch_table
    .long op_shr - o5s_dispatch_table
    .long op_eq - o5s_dispatch_table
    .long op_ne - o5s_dispatch_table
    .long op_lt - o5s_dispatch_table
    .long op_le - o5s_dispatch_table
    .long op_gt - o5s_dispatch_table
    .long op_ge - o5s_dispatch_table
    .long op_lnot - o5s_dispatch_table
    .long op_jmp - o5s_dispatch_table
    .long op_jmp_if_zero - o5s_dispatch_table
    .long op_jmp_if_nonzero - o5s_dispatch_table
    .long op_call_builtin - o5s_dispatch_table
    .long op_call - o5s_dispatch_table
    .long op_ret - o5s_dispatch_table
    .long op_halt - o5s_dispatch_table
    .long op_loop_step - o5s_dispatch_table
    .long op_add_local - o5s_dispatch_table
    .long op_inc_local - o5s_dispatch_table
    .long op_dec_local - o5s_dispatch_table
