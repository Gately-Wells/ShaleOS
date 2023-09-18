org 0x7C00
bits 16


%define ENDL 0x0D, 0x0A



bdb_oem:                    db 'MSWIN4.1'           ; 8 bytes
bdb_bytes_per_sector:       dw 512
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 1
bdb_fat_count:              db 2
bdb_dir_entries_count:      dw 0E0h
bdb_total_sectors:          dw 2880                 ; 2880 * 512 = 1.44MB
bdb_media_descriptor_type:  db 0F0h                 ; F0 = 3.5" floppy disk
bdb_sectors_per_fat:        dw 9                    ; 9 sectors/fat
bdb_sectors_per_track:      dw 18
bdb_heads:                  dw 2
bdb_hidden_sectors:         dd 0
bdb_large_sector_count:     dd 0
ebr_drive_number:           db 0                    ; 0x00 floppy, 0x80 hdd, useless
                            db 0                    ; reserved
ebr_signature:              db 29h
ebr_volume_id:              db 12h, 34h, 56h, 78h   ; serial number
ebr_volume_label:           db 'ShaleOS    '        ; 11 bytes, padded with spaces
ebr_system_id:              db 'FAT12   '           ; 8 bytes


start:
	jmp main


; Prints a string to the screen
; Params:
;   - ds:si points to string



puts:
	; save registers we will modify
	push si
	push ax

.loop:
	lodsb			; loads next character in al
	or al, al		; verify if next character is null?
	jz .done

	mov ah, 0x0e	; call bios interrupt
	mov bh, 0
	int 0x10

	jmp .loop

.done:
	pop ax
	pop si
	ret

main:

	; setup data segments
	mov ax, 0 			; can't write to ds/es directly
	mov ds, ax
	mov es, ax

	; setup stack
	mov ss, ax
	mov sp, 0x7C00 		; stack grows downwards from where we are loaded in memory

	; read from BIOS
	mov [ebr_drive_number], dl

	mov ax, 1
	mov cx, 1
	mov bx, 0x7E00
	call disk_read

	; print message
	mov si, msg_boot
	call puts


	hlt

floppy_error:
	mov si, msg_read_fail
	call puts
	jmp wait_key_and_reboot

wait_key_and_reboot:
	mov ah, 0
	int 16h
	jmp 0FFFFh:0		; to beginning of BIOS

.halt:
	cli					; disable interupts
	hlt
;
; Disk
;

;
; Converts an LBA address to a CHS address
; Parameters:
;	- ax: LBA address
; Returns:
;	- cx [bits 0-5]: sector number
;	- cx [bits 6-15]: cylinder
;	- dh: head
;

lba_to_chs:

	push ax
	push dx


	xor dx, dx							; dx = 0
	div word [bdb_sectors_per_track]	; ax = LBA / SectorsPerTrack


	inc dx								; dx = (LBA % SectorsPerTrack + 1) = sector
	mov cx, dx							; cx = sector

	xor dx, dx							; dx = 0
	div word [bdb_heads]				; ax = (LBA / SectorsPerTrack) / Heads = cylinder
										; dx = (LBA / SectorsPerTrack) % Heads = head
	mov dh, dl							; dl = head
	mov ch, al 							; ch = cylinder (lower 8 bits)
	shl ah, 6
	or cl, ah							; put upper 2 bits of cylinder in CL

	pop ax
	mov dl, al							; restore DL
	pop ax
	ret

;
; Reads sectors from a disk
; Parameters:
;	- ax: LBA address
;	- cl: number of sectors to read (up to 128)
;	- dl: drive number
;	- es:bx: memory address where to store read data

disk_read:

	push ax
	push bx
	push cx
	push dx
	push di

	push cx							; temporarily save CL (number of sectors to read)
	call lba_to_chs 					; compute CHS
	pop ax								; AL = number of sectors to read
	mov ah, 02h

	mov di, 3							; retry count (assuming floppy fail)


.retry:
	pusha								; save all registers
	stc 								; set carry flag if BIOS doesn't already
	int 13h								; carry flag cleared
	jnc .done							; jump if carry not set

	; if read failed
	popa
	call disk_reset

	dec di
	test di, di
	jnz .retry

.fail:
	jmp floppy_error

.done:
	popa

	push di
	push dx
	push cx
	push bx
	push ax
	ret


;
;	Resets disk controller
;	Parameters:
;		dl: drive number
;
disk_reset:
	pusha
	mov ah, 0
	stc
	int 13h
	jc floppy_error
	popa
	ret

msg_boot: db  'ShaleOS Started!', ENDL, 0
msg_read_fail: db 'Error while reading from disk.', ENDL, 0


times 510-($-$$) db 0
dw 0AA55h
