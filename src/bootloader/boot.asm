org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A

;
; FAT12 HEADER
;
jmp short entry
nop

bdb_oem:                    db 'MSWIN4.1'           ; 8 bytes
bdb_bytes_per_sector:       dw 512
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 1
bdb_fat_count:              db 2
bdb_dir_entries_count:      dw 0E0h
bdb_total_sectors:          dw 2880                 ; 2800 * 512 = 1.44MB   
bdb_media_descriptor_type:  db 0F0h                 ; F0 = 3.5" floppy disc
bdb_sectors_per_fat:        dw 9                    ; 9 sectors/fat
bdb_sectors_per_track:      dw 18                   ; 18 sectors/track
bdb_heads:                  dw 2       
bdb_hidden_sectors:         dd 0
bdb_large_sector_count:     dd 0

; extended boot record
ebr_driver_number:          db 0                    ; 0x00 floppy, 0x80 hard disk
                            db 0                    ; reserved
ebr_signature:              db 29h
ebr_volume_id:              db 12h, 34h, 56h, 78h   ; serial number, value doesn't matter
ebr_volume_label:           db 'CucumberCan'        ; 11 bytes
ebr_system_id:              db 'FAT12   '           ; 8 bytes


;
; Code goes here
;

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

    ; read something from floppy disk
    ; BIOS should set dl to drive number
    mov [ebr_driver_number], dl

    mov ax, 1               ; LBA = 1, second sector
    mov cl, 1               ; 1 sector to read
    mov bx, 0x7E00          ; read to 0x7E00
    call disk_read

    ; print message
    mov si, msg_hello
    call puts


    cli                     ; disable interrupts, so we can't get out of halt state
    hlt

;
; Error handlers
;

error_floppyError:
    mov si, msg_read_failed
    call puts
    jmp wait_key_and_reboot

wait_key_and_reboot:
    mov si, msg_wait_key_reboot
    call puts

    mov ah, 0
    int 16h                 ; wait for key press
    jmp 0FFFFh:0            ; jump to BOIS address, reboot

.halt:
    cli                     ; disable interrupts, so we can't get out of halt state
    jmp .halt

;
; Disk routines
;


;
; Convert LBA to CHS address
; Params:
;   - ax: LBA address
; Returns:
;   - cx [bits 0-5]: sector number
;   - cx [bits 6-15]: cylinder number
;   - dh: head
;

lba_to_chs:
    push ax
    push dx

    xor dx, dx                              ; clear dx
    div word [bdb_sectors_per_track]        ; ax = LBA / sectors_per_track
                                            ; dx = LBA % sectors_per_track

    inc dx                                  ; dx = (LBA % sectors_per_track) + 1 == sector number
    mov cx, dx                              ; cx = sector number

    xor dx, dx
    div word [bdb_heads]                    ; ax = (LBA / sectors_per_track) / heads
                                            ; dx = (LBA / sectors_per_track) % heads

    mov dh, dl                              ; dh = head number
    mov ch, al                              ; ch = cylinder number (lower 8 bits)
    shl ah, 6                               ; ah = cylinder number (upper 2 bits)
    or cl, ah                               ; cl = cylinder number (upper 2 bits) | cylinder number (lower 8 bits)

    pop ax                                  ; restore dx in ax
    mov dl, al
    pop ax
    ret


; 
; Reads sectors from a disk
; Params:
;   - al: LBA address
;   - cl: number of sectors to read (up to 128)
;   - dl: drive number
;   - es:bx: memory location where to store the read data
;
disk_read:
    push ax                                 ; backup registers
    push bx
    push cx
    push dx
    push di

    push cx                                 ; backup cx (number of sectors to read)
    call lba_to_chs                         ; convert LBA to CHS
    pop ax                                  ; restore cx in ax (number of sectors to read)

    mov ah, 0x02
    mov di, 3                               ; retry 3 times (floppy disk is very unreliable)

.retry:
    pusha                                   ; backup all registers
    stc                                     ; set carry flag (error flag, some bios won't set it)
    int 13h                                 ; carry flag will be cleared if success
    jnc .done                               ; jump if carry flag is cleared
    ; read failed
    popa
    call disk_reset

    dec di
    test di, di
    jnz .retry

.fail:
    ; all attempts failed
    jmp error_floppyError

.done:
    popa                                    ; restore all registers
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

;
; Reset disk controller
; Params:
;   - dl: drive number
;
disk_reset:
    pusha
    mov ah, 0
    stc
    int 13h
    jc error_floppyError
    popa
    ret


msg_hello:              db 'Hello, World!', ENDL, 0
msg_read_failed:        db '[ERROR] Read from disk failed!', ENDL, 0
msg_wait_key_reboot:    db ENDL, 'Press any key to reboot...', 0


times 510 - ($-$$) db 0
dw 0AA55h

