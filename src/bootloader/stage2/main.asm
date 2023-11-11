bits 16

section _ENTRY class=OCDE

extern _cstart_
global entry

entry:
    cli
    mov ax, ds
    mov ss, ax
    mov sp, 0
    mov bp, sp
    sti

    ; expect boot drive in dl, sent is to _cstart_ as argument
    xor dh, dh
    push dx
    call _cstart_

    cli
    hlt
