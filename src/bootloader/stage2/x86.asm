bits 16

section _TEXT class=Code

global _x86_Video_WriteCharTeletype
_x86_Video_WriteCharTeletype:
    push bp         ; save bp
    mov bp, sp      ; init new call frame

    ; save bx
    push bx

    ; [bp + 0] -- old call frame
    ; [bp + 2] -- return address (2 bytes)
    ; [bp + 4] -- character to print (1 byte)
    ; [bp + 5]*-- color (1 byte)
    ; [bp + 6] -- second arg (page)
    ; note: bytes are converted to words
    mov ah, 0Eh
    mov al, [bp + 4]
    mov bh, [bp + 6]

    int 10h

    ; restore bx
    pop bx

    ; restore all call frame
    mov sp, bp
    pop bp
    ret
