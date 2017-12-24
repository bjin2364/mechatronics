		LIST P=16F747
		title "On-Off Control"


;***********************************************************
;
; The overall purpose of the code is to demonstrate four different modes of operation of the solenoid and microcomputer board system
;
; The four different modes are as follows:
;
; Mode 1 - Basic Test (Process Checking Application)
; Pressing the red button toggles the state of the solenoid (engaged or disengaged).
;
; Mode 2 - Basic Timing Control (Toaster Oven Application)
; Pressing the red button reads a control potentiometer and engages the solenoid for a quarter of the value in seconds.
; If the red button is pressed before timing is completed, the timing sequence restarts.
; After finishing, pressing the red button again repeats the process.
; If the reading of the A/D converter is 0, a fault is indicated.
;
; Mode 3 - Basic Feedback Control (Air Conditioning Application)
; Pressing the red button activates the control, which compares the value of the control potentiometer with that of a setpoint (0x70).
; If the control potentiometer reads higher than 0x70, the solenoid engages. Otherwise the solenoid retracts.
; While the control is active the indicator flashes.
; If the reading of the A/D converter is 0, a fault is indicated.
;
; Mode 4 - Feedback, Backup Circuit, Fault Detection, Fault Recovery (Sump Pump Application)
; Pressing the red button turns on the main transistor.
; The optical sensor is checked to ensure that the solenoid has retracted.
; If after 10 seconds the optical sensor does not indicate the solenoid has retracted, a fault is indicated.
; As soon as the optical sensor indicates that the solenoid has retracted, the reduced transistor is turned on and the main transistor is turned off.
; The reduced transistor then stays on for one quarter the value of the control potentiometer in seconds.
; If the optical sensor indicates that the solenoid has disengaged when the reduced transistor is on, restart the whole sequence again (one time).
; If the optical sensor indicates that the solenoid has disengaged a second time when the reduced transistor is on, a fault is indicated.
; If the solenoid is turned off and the optical sensor indicates that the solenoid is still retracted in 10 seconds, a fault is indicated.
; If the reading of the A/D converter is 0, a fault is indicated.

; For all modes, pressing the green button after operation is finished enters a mode indicated by the octal switch.

; This program runs on the Mechatronics microcomputer board.
; The hardware on this microcomputer board is as follows:
; Port A pin 0 is connected to the precision potentiometer 
; Port B pins 0-3 are connected to 4 Red LED "idiot" lights,
; Port C pins 0,1 are connected to the green and red pushbutton
; Port D pins 0,1 are connected to the main and reduced transistor for the solenoid
; Port E pins 0-2 are connected to the octal switch
; 
;
; 
; How registers are used
;
; State register
; bit 0
; bit 1
; bit 2
; bit 3
; bit 4
; bit 5
; bit 6
; bit 7
;
;
;
;***********************************************************

		#include <P16F747.INC>
		__CONFIG _CONFIG1, _FOSC_HS & _CP_OFF & _DEBUG_OFF & _VBOR_2_0 & _BOREN_0 & _MCLR_ON & _PWRTE_ON & _WDT_OFF
		__CONFIG _CONFIG2, _BORSEN_0 & _IESO_OFF & _FCMEN_OFF


; Variable declarations
Count 	equ 	20h 					; the counter
Temp 	equ 	21h 					; a temporary register
Octal 	equ 	22h 					; the octal switch register
Mode 	equ 	23h 					; the mode register
State	equ		24h						; the state register
Timer2 	equ 	25h 					; timer storage variable
Timer1 	equ 	26h 					; timer storage variable
Timer0 	equ 	27h 					; timer storage variable
TenSec	equ		28h						; 10 second timer storage variable
Restart	equ		29h						; restart counter
F_LED	equ		30h						; variable for blinking fault LED

		org 00h 						; Assembler directive - Reset Vector

		goto initPort					; Initialization routine

		org 04h 						; interrupt vector
		goto isrService 				; jump to interrupt service routine (dummy)

		org 15h 						; Beginning of program storage

;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;
; Port Initialization

initPort

		clrf 	PORTA 					; Clear Port A output latches
		clrf 	PORTB 					; Clear Port B output latches
		clrf 	PORTC 					; Clear Port C output latches
		clrf 	PORTD 					; Clear Port D output latches		
		clrf 	PORTE 					; Clear Port E output latches
		clrf	State					; Clear State
		bsf 	STATUS,RP0 				; Set bit in STATUS register for bank 1
		movlw 	h'FF'		 			; move hex value FF into W register
		movwf 	TRISA 					; Configure Port A as all inputs
		movwf 	TRISC 					; Configure Port C as all inputs		
		movlw 	h'F0'					; move hex value F0 into the W register
		movwf 	TRISB 					; Configure Port B pins 0-3 as output and 4-7 as input
		movlw	B'00000100'				; move binary value 00000100 into the W register
		movwf 	TRISD 					; Configure Port D pin 2 as input and all other pins as output
		movlw	B'00000111'				; move binary value 00000111 into the W register
		movwf 	TRISE 					; Configure Port E pins 0-2 as input
		bcf 	STATUS,RP0 				; Clear bit in STATUS register for bank 0
		clrf 	Count 					; zero the counter
		bsf		STATUS,C				; set the carry bit
		movlw	h'0b'					; move decimal value 10+1 to W register
		movwf	TenSec					; set TenCount to 1+1
		movlw	h'02'					; move decimal value 1+1 to W register
		movwf	Restart					; set Restart to 1+1
		clrf	State					; clear the State register

initAD

		bsf 	STATUS,RP0 				; select register bank 1
		movlw 	B'00001110' 			; set A/D port configuration bit AN0 as analog input
		movwf 	ADCON1 					; move to special function A/D register
		bcf 	STATUS,RP0 				; select register bank 0
		movlw 	B'01000001' 			; select 8 * oscillator, analog input 0, turn on
		movwf 	ADCON0 					; move to special function A/D register

;
;
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


;############################################################
; This routine is a software delay of 10uS required for the A/D setup.
; At a 4Mhz clock, the loop takes 3uS, so initialize the register Temp with
; a value of 3 to give 9uS, plus the move etc. should result in
; a total time of > 10uS.

SetupDelay

		movlw 	03h 					; load Temp with hex 3
		movwf 	Temp
delay
		decfsz 	Temp, F 				; Delay loop
		goto 	delay

;
;############################################################

initPress

		btfsc 	PORTC,0 				; see if green button pressed upon processor reset
		goto 	GreenPress 				; green button is pressed - goto routine
		goto 	initPress 				; keep checking

waitPress

		btfsc 	PORTC,0 				; see if green button pressed
		goto 	GreenPress 				; green button is pressed - goto routine
		btfsc 	PORTC,1 				; see if red button pressed
		goto 	RedPress 				; red button is pressed - goto routine
		goto 	waitPress 				; keep checking

GreenPress

		btfss 	PORTC,0 				; see if green button still pressed
		goto 	waitPress 				; noise - button not pressed - keep checking

GreenRelease

		btfsc 	PORTC,0 				; see if green button released
		goto 	GreenRelease 			; no - keep waiting
		call 	SwitchDelay 			; let switch debounce

		bcf		PORTD,0					; clear main transistor bit
		bcf		PORTD,1					; clear reduced transistor bit


		movf	PORTE,0					; move PORTE (octal switch) contents to the W register
		sublw	h'08'					; literal 00001000 minus W register contents. This equals Mode + 1
		movwf	Octal					; move W register to Octal register
		clrf	Mode					; clear the Mode register

;############################################################

; Setup Mode register so that the position of the bit corresponds to the mode number you are in.
; Check every bit of the Mode register to see which mode you are in. 
; If you are in mode 1-4 set the LED of the cooresponding mode on and return to waitPress. 
; If you are not in mode 1-4 go to Fault.

ModeSelector
		
		rlf		Mode,1					; rotate left Mode
		decfsz	Octal,1					; decrement Octal, skip if 0
		goto	ModeSelector			; loop until octal is 0 (this line is skipped when Octal is decremented from 1 to 0)
		clrf	PORTB					; clear PORTB to turn off LED
		
		btfsc	Mode,0					; test bit 0, skip if clear
		goto	Fault					; go to Fault if bit 0 is set

		btfsc	Mode,1					; test bit 1, skip if clear
		bsf		PORTB,0					; turn on LED 1 for mode 1 if bit 1 is set
		btfsc	Mode,2					; test bit 2, skip if clear
		bsf		PORTB,1					; turn on LED 2 for mode 2 if bit 2 is set
		btfsc	Mode,3					; test bit 3, skip if clear
		bsf		PORTB,0					; turn on both LED 1 for mode 3 if bit 3 is set 
		btfsc	Mode,3					; test bit 3, skip if clear
		bsf		PORTB,1					; turn on both LED 2 for mode 3 if bit 3 is set 
		btfsc	Mode,4					; test bit 4, skip if clear
		bsf		PORTB,2					; turn on LED 3 for mode 4 if bit 4 is set

		btfsc	Mode,5					; test bit 5, skip if clear
		goto	Fault					; go to Fault if bit 5 is set

		btfsc	Mode,6					; test bit 6, skip if clear
		goto	Fault					; go to Fault if bit 6 is set

		btfsc	Mode,7					; test bit 7, skip if clear
		goto	Fault					; go to Fault if bit 7 is set

		goto	waitPress				; go to waitPress for Mode 1-4 (equivalent to "beginning" each mode)

;
;############################################################


RedPress

		btfss 	PORTC,1 				; see if red button still pressed
		goto 	waitPress 				; noise - button not pressed - keep checking

RedRelease

		btfsc 	PORTC,1 				; see if red button released
		goto 	RedRelease 				; no - keep waiting
		call 	SwitchDelay 			; let switch debounce

		btfsc	Mode,1					; test Mode bit 1, skip if clear
		goto	Mode1					; if Mode bit 1 is set, go to Mode1

		bsf 	ADCON0,GO 				; start A/D conversion
		call	potCheck				; call potCheck routine to check if A/D conversion is finished, store A/D value and check if A/D value is 0
		btfsc	Mode,2					; test Mode bit 2, skip if clear
		goto	Mode2					; if Mode bit 2 is set, go to Mode2
		btfsc	Mode,3					; test Mode bit 3, skip if clear
		goto	initMode3Timer			; if Mode bit 3 is set, go to Mode3
		btfsc	Mode,4					; test Mode bit 4, skip if clear
		goto	Mode4					; if Mode bit 4 is set, go to Mode4

		goto	Fault					; goto Fault if it doesnt go to mode 1-4


potCheck

		btfsc 	ADCON0,GO 				; check if A/D is finished
		goto 	potCheck 				; loop right here until A/D finished
		btfsc 	ADCON0,GO 				; make sure A/D finished
		goto 	potCheck				; A/D not finished, continue to wait

		btfsc	Mode,3					; check if in Mode 3
		goto	potCheckValue			; if in Mode 3, go to potCheckValue

		movf	ADRESH,W				; move A/D value to W register
		movwf	Count					; move W register to Count
		bcf		STATUS,C				; clear the carry bit
		rrf		Count,F					; rotate the Count register right
		bcf		STATUS,C				; clear the carry bit
		rrf		Count,F					; rotate the Count register right
		incf	Count,F					; increment Count, store result in Count
		decfsz	Count,F					; decrement Count, skip if 0, store result back in Count
		return							; return to calling routine
		goto	Fault					; goto Fault if Count decrements to 0

potCheckValue

		incf	ADRESH,F				; increment ADRESH register, store in ADRESH
		decfsz	ADRESH,F				; decrement ADRESH, skip if result is zero
		return							; return to calling routine
		goto	Fault					; if ADRESH is 0, go to Fault

Mode1

		comf	PORTD,W					; complement PORTD, store in W register
		movwf	State					; move W register to State register
		btfsc	State	,0				; test bit 0 of State, skip if clear
		bsf		PORTD,0					; if bit 0 of State is set, set main transistor (PORTD pin 0)
		btfss	State	,0				; test bit 0 of State, skip if set
		bcf		PORTD,0					; if bit 0 of State is clear, clear main transistor (PORTD pin 0)
		goto 	waitPress				; go to waitPress

Mode2

		bsf		PORTD,0					; turn on main transistor
										; goto timeLoop

timeLoop

		movlw 	06h 					; get most significant hex value + 1
		movwf 	Timer2 					; store it in Timer2 register
		movlw 	16h 					; get next most significant hex value
		movwf 	Timer1 					; store it in Timer1 register
		movlw 	15h 					; get least significant hex value
		movwf 	Timer0 					; store it in Timer0 register

delay2		

		decfsz 	Timer0,F 				; Delay loop
		goto 	delay2					; loop back until Timer0 will decrement to 0
		decfsz 	Timer1,F 				; Delay loop
		goto 	delay2					; loop back until Timer1 will decrement to 0
		call	checkRedPressMode2		; check for a red press while the timer counts down
		decfsz 	Timer2,F 				; Delay loop
		goto 	delay2					; loop back until Timer2 will decrement to 0

		decfsz	Count,F					; decrement Count, skip if 0
		goto	timeLoop				; loop back
		bcf		PORTD,0					; clear PORTD to turn main transistor off
		goto	waitPress				; go to waitPress


checkRedPressMode2

		btfsc 	PORTC,1 				; see if red button pressed
		goto 	RedPressMode23			; red button is pressed - goto RedPressMode23 routine
		return							; red button is not pressed - return to delay2

RedPressMode23

		btfss 	PORTC,1 				; see if red button still pressed
		return							; noise - button not pressed - keep checking
		btfsc	Mode,2					; skip if not in Mode2
		goto	RedRelease				; if in Mode2 goto RedRelease

										;goto	RedReleaseMode3

RedReleaseMode3

		btfsc 	PORTC,1 				; see if red button released
		goto 	RedReleaseMode3 		; no - keep waiting
		call 	SwitchDelay 			; let switch debounce
		
		bcf		PORTD,0					; turn off main transistor
		bsf		PORTB,0					; turn on LED 1
		bsf		PORTB,1					; turn on LED 2

		goto	waitPress

initMode3Timer

		movlw	61h						; get most significant hex value +1
		movwf	Timer1					; store it in Timer1 register
		movlw	h'A8'					; get next most significant hex value
		movwf	Timer0					; store it in Timer0 register

Mode3	

		call	ledTimerMode3			; timer to ensure that the indicator lights blink every second

		movlw	h'70'					; move hex value to W
		subwf	ADRESH,0				; subract hex value from Count

		btfsc	STATUS,Z				; if z=0, skip next line. 
		bcf		STATUS,C				; if z=1 set c=0
		btfsc	STATUS,C				; skip if carry bit is clear (Count < hex value)
		bsf		PORTD,0					; turn on main transistor
		btfss	STATUS,C				; skip if carry bit is set (Count > hex value)
		bcf		PORTD,0					; turn off main transistor

										; goto checkRedPressMode3

checkRedPressMode3

		btfsc 	PORTC,1 				; see if red button pressed
		goto 	RedPressMode23			; red button is pressed - goto RedPressMode2 routine
		
		bsf		ADCON0,GO				; start A/D conversion
		call	potCheck				; read potentiometer again
		goto	Mode3					; goto Mode3

Mode4

		bsf		PORTD,0					; turn on main transistor
		call	timeLoop2				; check optical sensor, fault if it is low after 10 seconds

		;continue mode 4

		bsf		PORTD,1					; turn on 2nd transistor
		call	timeLoop8				; delay for milliseconds (currently 1s delay)
		bcf		PORTD,0					; turn off main transistor
		call	timeLoop2				; check optical sensor for 1/4 of pot value in seconds

timeLoop2

		movlw 	04h 					; get most significant hex value + 1
		movwf 	Timer2 					; store it in count register
		movlw 	01h 					; get next most significant hex value
		movwf 	Timer1 					; store it in count register
		movlw 	90h 					; get least significant hex value
		movwf 	Timer0 					; store it in count register

		btfsc	PORTD,1					; check if reduced transistor is on
		goto	delay5					; if reduced transistor is on, goto delay5
										; goto delay 4 if reduced transistor is off (main transistor is on)
delay4
		
		btfsc	PORTD,2					; read optical sensor, skip if low
		return							; continue Mode4 if optical sensor is high
	
		decfsz 	Timer0,F 				; Delay loop
		goto 	delay4					; loop back until Timer0 will decrement to 0
		decfsz 	Timer1,F 				; Delay loop
		goto 	delay4					; loop back until Timer1 will decrement to 0
		decfsz 	Timer2,F 				; Delay loop
		goto 	delay4					; loop back until Timer2 will decrement to 0

		decfsz	TenSec,F				; decrement 10 second counter
		goto	timeLoop2				; if result of decrement is non-zero, goto timeLoop2
		goto	Fault					; if 10 second counter runs down goto Fault

delay5

		btfss	PORTD,2					; read optical sensor
		goto	RestartMode				; go to RestartMode
	
		decfsz 	Timer0,F 				; Delay loop
		goto 	delay5					; loop back until Timer0 will decrement to 0
		decfsz 	Timer1,F 				; Delay loop
		goto 	delay5					; loop back until Timer1 will decrement to 0
		decfsz 	Timer2,F 				; Delay loop
		goto 	delay5					; loop back until Timer2 will decrement to 0

		decfsz	Count,F					; decrement Count, skip if zero
		goto	timeLoop2				; if Count is non-zero, goto timeLoop2
		goto	checkOff4				; if Count is zero, turn off reduced transistor and check that it is off

RestartMode		
		
		btfss	Restart,1				; test Restart register bit 1, skip if set
		goto	Fault					; if Restart register is clear (has already been restarted once), goto Fault
		decf	Restart,F				; decrement Restart counter
		bcf		PORTD,1					; turn off the main transistor
		goto	Mode4					; goto Mode4

checkOff4

		bcf		PORTD,1					; turn off the reduced transistor
		movlw	h'02'					; move literal 0x02 to the W register 
		movwf	Restart					; resets the Restart counter
										; goto timeLoop3
timeLoop3

		movlw 	03h 					; get most significant hex value + 1
		movwf 	Timer2 					; store it in count register
		movlw 	9Fh 					; get next most significant hex value
		movwf 	Timer1 					; store it in count register
		movlw 	90h 					; get least significant hex value
		movwf 	Timer0 					; store it in count register

delay6
		
		btfss	PORTD,2					; read optical sensor
		goto	waitPress				; go to waitPress		

		decfsz 	Timer0,F 				; Delay loop
		goto 	delay6					; loop back until Timer0 will decrement to 0
		decfsz 	Timer1,F 				; Delay loop
		goto 	delay6					; loop back until Timer1 will decrement to 0
		decfsz 	Timer2,F 				; Delay loop
		goto 	delay6					; loop back until Timer2 will decrement to 0

		decfsz	TenSec,F				; decrement 10 second counter
		goto	timeLoop3				; goto timeLoop3
										; goto Fault if TenCount reaches zero
Fault

		bcf		PORTD,0					; turn off main transistor
		bcf		PORTD,1					; turn off reduced transistor

		; Flash Fault LED					
		
		comf	PORTB,W					; complement PORTB, store in W register
		movwf	F_LED					; move W register to F_LED register
		btfsc	F_LED,3					; test bit 3 of F_LED, skip if clear
		bsf		PORTB,3					; set PORTB bit 3 to turn on fault LED
		btfss	F_LED,3					; test bit 3 of F_LED, skip if set
		bcf		PORTB,3					; clear PORTB bit 3 to turn off fault LED
		call	timeLoop8				; call timeLoop8 (1second delay)
		
		goto	Fault

SwitchDelay

		movlw 	D'20' 					; load Temp with decimal 20
		movwf 	Temp

delay3
		decfsz 	Temp, F 				; 60 usec delay loop
		goto 	delay3 					; loop until count equals zero
		return 							; return to calling routine

timeLoop8

		movlw 	06h 					; get most significant hex value + 1
		movwf 	Timer2 					; store it in count register
		movlw 	16h 					; get next most significant hex value
		movwf 	Timer1 					; store it in count register
		movlw 	15h 					; get least significant hex value
		movwf 	Timer0 					; store it in count register

delay8		

		decfsz 	Timer0,F 				; Delay loop
		goto 	delay8					; loop back until Timer0 will decrement to 0
		decfsz 	Timer1,F 				; Delay loop
		goto 	delay8					; loop back until Timer1 will decrement to 0
		decfsz 	Timer2,F 				; Delay loop
		goto 	delay8					; loop back until Timer2 will decrement to 0
		return

ledTimerMode3

		decfsz	Timer0,F				; Delay loop				
		return							; return to Mode3 
		decfsz	Timer1,F				; Delay loop, skip to blinkMode3 when finished
		return							; return to Mode3
		
blinkMode3

		movf	PORTB,W					; move PORTB to W register
		sublw	h'03'					; subtract W register from hex value '03' (toggles LEDs)
		movwf	PORTB					; move W register to PORT B

		movlw	61h						; reset Timer1 value
		movwf	Timer1					; move W register value to Timer1
		movlw	h'A8'					; reset Timer2 value
		movwf	Timer0					; move W register value to Timer0
		return							; return to calling routine

;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
;
; Note: this is a dummy interrupt service routine. It is good programming
; practice to have it. If interrupts are enabled (which they should not be)
; and if an interrupt occurs (which should not happen), this routine safely
; hangs up the microcomputer in an infinite loop.

isrService
		goto 	isrService 				; error - stay here
;
;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~



		END 							; Assembler directive - end of program