org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A

entry:
    jmp main

; 
; Prints a string to the screen
; Params:
;   - ds:si points to string
;
puts:
    ; backup registers we will modify
    push si
    push ax

.loop:
    lodsb                   ; load next char
    or al, al               ; check if next char is null
    jz .break

    ; print char
    mov ah, 0x0E            ; teletype output
    mov bh, 0x00            ; page number
    int 10h

    jmp .loop

.break:
    pop ax
    pop si
    ret



main:

    ; setup data segment
    mov ax, 0               ; can't write to ds/es directly
    mov ds, ax
    mov es, ax

    ; setup stack
    mov ss, ax
    mov sp, 0x7C00          ; stack grows downwards where this program (the bootloader) is loaded

    ; print message
    mov si, msg_hello
    call puts

    hlt

.halt:
    jmp .halt


msg_hello: db 'Hello, World!', ENDL, 0


times 510 - ($-$$) db 0
dw 0AA55h

