LIST P=16F747
title "On-Off Control"

;***********************************************************
;
; This program runs on the Mechatronics microcomputer board.
; On this microcomputer board:
; The Precision Potentiometer is Port A, Pin 0
; The Red LEDs are on Port B, Pins 0, 1, 2, 3
; The Green Pushbutton is Port C, pin 0
; The Red Pushbutton is Port C, pin 1
;
;***********************************************************

#include <P16F747.INC>
__CONFIG _CONFIG1, _FOSC_HS & _CP_OFF & _DEBUG_OFF & _VBOR_2_0 & _BOREN_0 & _MCLR_ON & _PWRTE_ON & _WDT_OFF
__CONFIG _CONFIG2, _BORSEN_0 & _IESO_OFF & _FCMEN_OFF

; Variable declarations
Count 	equ 	20h 			; the counter
Temp 	equ 	21h 			; a temporary register
State 	equ 	22h 			; the program state register

		org 	00h 			; Assembler directive - Reset Vector

		goto 	initPort

		org 	04h 			; interrupt vector
		goto 	isrService 		; jump to interrupt service routine (dummy)
		org 15h 				; Beginning of program storage

;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;
; Port Initialization
initPort
		clrf PORTA 				; Clear Port A output latches
		clrf PORTB 				; Clear Port B output latches
		clrf PORTC 				; Clear Port C output latches
		clrf PORTD 				; Clear Port D output latches
		clrf PORTE 				; Clear Port E output latches
		bsf STATUS,RP0 			; Set bit in STATUS register for bank 1
		movlw B'11111111' 		; move hex value FF into W register
		movwf TRISA 			; Configure Port A as all inputs
		movwf TRISC 			; Configure Port C as all inputs
		movwf TRISE 			; Configure Port E as all inputs
		movlw h'f0' 			; move hex value 00 into the W register
		movwf TRISD 			; Configure Port B as 
		movwf TRISB 			; 
		bcf STATUS,RP0 			; Clear bit in STATUS register for bank 0

waitPress
		btfsc 	PORTC,0 		; see if green button pressed
		goto 	GreenPress 		; green button is pressed - goto routine
		btfsc 	PORTC,1 		; see if red button pressed
		goto 	RedPress 		; red button is pressed - goto routine
		goto 	waitPress	 	; keep checking
GreenPress
		btfss 	PORTC,0 		; see if green button still pressed
		goto 	waitPress		; noise - button not pressed - keep checking
GreenRelease
		btfsc 	PORTC,0 		; see if green button released
		goto 	GreenRelease 	; no - keep waiting
		call 	SwitchDelay 	; let switch debounce
		goto 	IncCount 		; increment the counter
RedPress
		btfss 	PORTC,1 		; see if red button still pressed
		goto 	waitPress 		; noise - button not pressed - keep checking
RedRelease
		btfsc 	PORTC,1 		; see if red button released
		goto 	RedRelease 		; no - keep waiting
		call 	SwitchDelay 	; let switch debounce
		decf 	Count,F 		; decrement count - store in register
		goto 	outCount 		; output the count on the PORTD LEDs

isrService
		goto 	isrService 		; error - - stay here

		END