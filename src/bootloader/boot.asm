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
    ; setup data segment
    mov ax, 0               ; can't write to ds/es directly
    mov ds, ax
    mov es, ax

    ; setup stack
    mov ss, ax
    mov sp, 0x7C00          ; stack grows downwards where this program (the bootloader) is loaded

    ; Some BIOSes might start us on 07C0:0000 insdead of 0000:7C00, make sure we are in the right place
    push es
    push word .after
    retf
.after:
    ; read something from floppy disk
    ; BIOS should set dl to drive number
    mov [ebr_driver_number], dl

    ; show loading message
    mov si, msg_loading
    call puts

    ; read driver parameters
    push es
    mov ah, 08h
    int 13h
    jc error_floppyError
    pop es

    and cl, 0x3F        ; cl = sectors per track, remove top 2 bits
    xor ch, ch
    mov [bdb_sectors_per_track], cx    ; sector / track

    inc dh
    mov [bdb_heads], dx                ; head count

read_FAT:
    ; LBA of root dir = reserved + fats * sectors_per_fat
    mov ax, [bdb_sectors_per_fat]       
    mov bl, [bdb_fat_count]
    xor bh, bh
    mul bx                              ; ax = (fats * sectors_per_fat)
    add ax, [bdb_reserved_sectors]      ; ax = LBA of root dir
    push ax

    ; size of root dir = (32 * number_of_entries) / bytes_per_sector
    mov ax, [bdb_dir_entries_count]
    shl ax, 5                           ; ax *= 32
    xor dx, dx                          ; dx = 0
    div word [bdb_bytes_per_sector]     ; number of sectors need to read

    test dx, dx                         ; if dx != 0, add 1
    jz .root_dir_after
    inc ax                              ; division remaing != 0, round up by adding 1

.root_dir_after:
    ; read root directory
    mov cl, al                          ; cl = number of sectors to read                          
    pop ax                              ; ax = LBA of root dir
    mov dl, [ebr_driver_number]         ; dl = driver number
    mov bx, buffer                      ; es:bx = memory location to store the read data
    call disk_read

    ; search for kernel.bin
    xor bx, bx                          ; how many entries already checked
    mov di, buffer                      ; point the current directory entry

.search_kernel:
    mov si, file_kernel_bin
    mov cx, 11                          ; compare up to 11 chars
    push di
    repe cmpsb                          ; repete while equal / compare string bytes
    pop di
    je .found_kernel

    add di, 32                          ; next directory entry, 32 is the size of a directory entry
    inc bx                              ; increase number of entries checked
    cmp bx, [bdb_dir_entries_count]     ; check if we checked all entries
    jl .search_kernel                   ; if not, search next entry

    ; kernel not found
    jmp error_kernelNotFound

.found_kernel:
    ; di should have the address to the entry.
    mov ax, [di + 26]                  ; first logical cluster field (offset 26)
    mov [kernel_cluster], ax

    ; load FAT from disk to memory
    mov ax, [bdb_reserved_sectors]
    mov bx, buffer
    mov cl, [bdb_sectors_per_fat]
    mov dl, [ebr_driver_number]
    call disk_read

    ; read kernel and process FAT chain
    mov bx, KERNEL_LOAD_SEGMENT
    mov es, bx
    mov bx, KERNEL_LOAD_OFFSET

.load_kernel_loop:
    ; read next cluster
    mov ax, [kernel_cluster]

    ; [TODO] hard coded value
    add ax, 31                          ; first cluster = (kernel_cluster - 2) * sectors_per_cluster + start_sector
                                        ; start sector = reserved + fats * root dir size

    mov cl, 1
    mov dl, [ebr_driver_number]
    call disk_read

    add bx, [bdb_bytes_per_sector]    ; move to next sector

    ; compute location of next cluster
    mov ax, [kernel_cluster]
    mov cx, 3
    mul cx
    mov cx, 2
    div cx                              ; ax = index of entry in fat = (kernel_cluster * 3) / 2, dx = cluster mod 2

    mov si, buffer
    add si, ax
    mov ax, [ds:si]                     ; read entry from fat table at index ax

    or dx, dx
    js .even
.odd:
    shr ax, 4
    jmp .next_cluster_after
.even:
    and ax, 0x0FFF

.next_cluster_after:
    cmp ax, 0x0FF8                      ; end of chain
    jae .read_finish

    mov [kernel_cluster], ax
    jmp .load_kernel_loop

.read_finish:
    ; jump to kernel
    mov dl, [ebr_driver_number]         ; boot device in dl

    mov ax, KERNEL_LOAD_SEGMENT         ; set segment registers
    mov ds, ax
    mov es, ax

    jmp KERNEL_LOAD_SEGMENT:KERNEL_LOAD_OFFSET


;
; Error handlers
;

error_floppyError:
    mov si, msg_read_failed
    call puts
    jmp wait_key_and_reboot

error_kernelNotFound:
    mov si, msg_kernel_not_found
    call puts
    jmp wait_key_and_reboot

wait_key_and_reboot:
    mov si, msg_wait_key_reboot
    call puts

    mov ah, 0
    int 16h                 ; wait for key press
    jmp 0FFFFh:0            ; jump to BOIS address, reboot


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


msg_loading:            db 'Loading ...', ENDL, 0
msg_prefix_error:       db '[ERROR]'
msg_read_failed:        db msg_prefix_error, '0', ENDL, 0       ; Read from disk failed!
msg_kernel_not_found:   db msg_prefix_error, '1', ENDL, 0       ; KERNEL not found!
msg_wait_key_reboot:    db ENDL, 'Press Any Button To Reboot', 0
file_kernel_bin:        db 'KERNEL  BIN', 0
kernel_cluster:         dw 0

KERNEL_LOAD_SEGMENT     equ 0x2000
KERNEL_LOAD_OFFSET      equ 0


times 510 - ($-$$) db 0
dw 0AA55h

buffer: