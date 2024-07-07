; Build params: ------------------------------------------------------------------------------
DEBUG_MENU	set 0
; Constants: ---------------------------------------------------------------------------------
	MD_PLUS_OVERLAY_PORT:			equ $0003F7FA
	MD_PLUS_CMD_PORT:				equ $0003F7FE
	MD_PLUS_RESPONSE_PORT:			equ $0003F7FC

	DATA_TRACK_POINTER_TABLE:		equ $00090002
	DATA_TRACK_DATA_START:			equ $000900EE

	; The code at $3D90 loads the latest command added to the sound command queue.
	PLAY_COMMAND_HANDLER:			equ $00004E28	; Anything below F0 counts as play command
	STOP_COMMAND_HANDLER:			equ $00004F54	; F1
	PAUSE_COMMAND_HANDLER:			equ $00005058	; F4
	RESUME_COMMAND_HANDLER:			equ	$000050F2	; F5
	UNKNOWN_COMMAND_HANDLER:		equ	$00005036 	; F3 Happens after fight
	FADE_OUT_COMMAND_HANDLER:		equ	$0000510E	; F6 Fadeout
	SPEED_UP_COMMAND_HANDLER:		equ	$00005122	; F7

	HD_TRIGGER_FUNCTION:			equ $0001441A
	TRIGGER_HD_ON_HP:				equ $39

	RAM_ENABLE_HD_TRIGGER:			equ	$FFFF986D
	RAM_HD_TRIGGER_VALUE:			equ	$FFFF9878
	RAM_PAUSE_STATE:				equ $FFFFC8C7
	RAM_MUSIC_SPEED_VALUE:			equ	$FFFFC8CA
	RAM_CURRENTLY_PLAYING_TRACK:	equ $FFFFFFF0

	RESET_VECTOR_ORIGINAL:			equ $00003AAA

; Overrides: ---------------------------------------------------------------------------------

	org		$4
	dc.l	DETOUR_RESET_VECTOR

	org		PLAY_COMMAND_HANDLER+$4
	jsr		DETOUR_PLAY_COMMAND_HANDLER
	nop
	nop

	org		STOP_COMMAND_HANDLER
	jsr		DETOUR_STOP_COMMAND_HANDLER

	;org	PAUSE_COMMAND_HANDLER	Not necessary as this handler later calls STOP_COMMAND_HANDLER

	org		RESUME_COMMAND_HANDLER
	jsr		DETOUR_RESUME_COMMAND_HANDLER
	nop

	org		FADE_OUT_COMMAND_HANDLER
	jsr		DETOUR_FADE_OUT_COMMAND_HANDLER
	nop

	org		SPEED_UP_COMMAND_HANDLER
	jmp		DETOUR_SPEED_UP_COMMAND_HANDLER
	nop

	org		HD_TRIGGER_FUNCTION+$14
	cmpi.b	#TRIGGER_HD_ON_HP,D0					; Compare lowest HP with our HD trigger value. If it's still higher, do not issue HD command
	bhi		DO_NOT_ISSUE_HD_COMMAND
	addi.b	#$1,(RAM_HD_TRIGGER_VALUE)				; Remember that HD command has already been triggered
	tst.b	(RAM_ENABLE_HD_TRIGGER)					; We do not want to trigger the HD tracks on the first fight
	beq		DO_NOT_ISSUE_HD_COMMAND
	cmpi.b	#$2,(RAM_HD_TRIGGER_VALUE)
	bhi		DO_NOT_ISSUE_HD_COMMAND
	jsr		$4f4									; Issue sndCmd F7
	nop
	nop
DO_NOT_ISSUE_HD_COMMAND

RETURN_SOUND_COMMAND_HANDLER

	org 	$3BE6									; Disable checksum validation
	nop

	org 	$3C10									; Disable checksum validation
	nop

	if DEBUG_MENU
	org		$A1C0 									;Debug sound test
	dc.w 	$79B6
	endif

	org		DATA_TRACK_POINTER_TABLE				; The code at $4E36 loads track pointers from this table. Here we
	rept	$30										; redirect all music track pointers towards $9CCB0. This means we
	dc.l	$9CCA0									; now have a lot of unused space we can use for our code.
	endr

	org		$9CCA0
	rept	$19
	dc.b	$00
	endr

; Detours: -----------------------------------------------------------------------------------

	org		DATA_TRACK_DATA_START

DETOUR_PLAY_COMMAND_HANDLER
	cmpi.b	#$30,D0									; At $30 the indices of SFX start
	bcs		IS_MUSIC								; If we are below $30, we have music
	cmpi.b	#$35,D0
	beq		IS_OPTIONS_MUSIC						; If the index is $35, we have music
	bra		DETOUR_EXIT_PLAY_COMMAND_HANDLER		; If D0 is $30 and above and not $35, leave detour
IS_OPTIONS_MUSIC
	subi.b	#$5,D0									; Subtract $5 from $35, so the MD+ track indices are continuous
IS_MUSIC
	addq.b	#$1,D0									; Add $1 to D0 to make track ids start at $1
	move.b	D0,(RAM_CURRENTLY_PLAYING_TRACK)		; Update the data for the currently playing track in RAM
	ori.w	#$1200,D0								; OR MD+ play command into D0
	move.w	D0,D1
	jsr		WRITE_MD_PLUS_FUNCTION
	moveq	#$0,D0									; Write $0 to D0 so the sound driver does nothing
DETOUR_EXIT_PLAY_COMMAND_HANDLER
	add		D0,D0									; Original game code
	add		D0,D0
	lea		DATA_TRACK_POINTER_TABLE,A0
	rts

DETOUR_STOP_COMMAND_HANDLER
	cmpi.b	#$12,D1									; For some reason, this command is also triggered after a fight.
	beq		DO_NOT_STOP								; In this case, D1 is always $12 and we skip the stop command.
	cmpi.b	#$17,(RAM_CURRENTLY_PLAYING_TRACK)		; For some reason, this command is triggered just after P2 joins during gameplay and the
	beq		DO_NOT_STOP								; "player joined" track just started playing. So check for that song and skip the stop command.
	move.w	#$1300,D1								; Move MD+ stop command into D1
	jsr		WRITE_MD_PLUS_FUNCTION
DO_NOT_STOP
	lea		$FFFFC5F2,A3							; Original game code
	moveq	#$8,D5
	rts

DETOUR_RESUME_COMMAND_HANDLER
	move.w	#$1400,D1								; Move MD+ resume command into D1
	jsr		WRITE_MD_PLUS_FUNCTION
	clr.b	RAM_PAUSE_STATE							; Original game code
	lea		$C61A,A3
	rts

DETOUR_FADE_OUT_COMMAND_HANDLER
	move.w	#$13FF,D1								; Move MD+ stop command + fade out time into D1
	jsr		WRITE_MD_PLUS_FUNCTION
	andi.w	#$FF,D1									; Original game code
	move.w	D1,($FFFFC8D0)
	rts

DETOUR_SPEED_UP_COMMAND_HANDLER
	cmpi.b	#$0,(RAM_MUSIC_SPEED_VALUE)				; The original fm music had multiple speed increases. Here we check to
	bne		DO_NOT_PLAY_HD							; make sure that the different music is only triggered on the first speed up.
	moveq	#$0,D1									; Empty D4
	move.b	(RAM_CURRENTLY_PLAYING_TRACK),D1		; Load currently playing track into D4
	addi.b	#$30,D1									; Add 48 to D4 since ingame tracks start at 2 and HD tracks start at 50
	ori.w	#$1200,D1								; OR the play command into D4
	jsr		WRITE_MD_PLUS_FUNCTION
DO_NOT_PLAY_HD
	addi.b	#$1,(RAM_MUSIC_SPEED_VALUE)				; Increase the speed up counter
	rts



DETOUR_RESET_VECTOR
	move.w	#$1300,D1								; Move MD+ stop command into D1
	jsr		WRITE_MD_PLUS_FUNCTION
	incbin	"intro.bin"								; Show MD+ intro screen
	jmp		RESET_VECTOR_ORIGINAL					; Return to game's original entry point

; Helper Functions: --------------------------------------------------------------------------



WRITE_MD_PLUS_FUNCTION:
	move.w	#$CD54,(MD_PLUS_OVERLAY_PORT)			; Open interface
	move.w	D1,(MD_PLUS_CMD_PORT)					; Send command to interface
	move.w	#$0000,(MD_PLUS_OVERLAY_PORT)			; Close interface
	rts
