org 0x0
bits 16

%define ENDL 0x0D, 0x0A

entry:
    jmp main




main:
    ; print message
    mov si, msg_hello
    call puts

.halt:
    cli
    hlt

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



msg_hello: db 'Hello, World from KERNEL!', ENDL, 0


