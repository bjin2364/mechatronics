		LIST P=16F747
		title "Thermal Systems Case Study"


;***********************************************************
; The overall purpose of this code is to demonstrate a thermal closed loop control system using the pic16F747
;
; The logic for the control loop is given below:
; 1) Check to see if the switch is on
; 2) If the switch is on, read the ambient and plate temperatures
; 3) Determine the hysteresis limits according to the ambient temperature reading
; 4) Determine where the plate temperature falls with respect to the hysteresis limits
; 5) Heat, cool, or maintain the previous state, depending on the result from step 4. Turn on correct LED
; 6) If the switch is off, the fan, heater, and LEDs will turn off
;
; Hardware:
;Port A - Pin 1,2 are analog inputs for ambient air temperature and plate temperature respectively.
;		  Pin 3 used for reference voltage 
;Port C - Pin 5 is digital input for the toggle switch
;Port D - Pin 0,1,2 control LEDs to indicate fan/hysteresis band/heater respectively.
;         Pin 6 and 7 control the heater and fan respectively (all outputs)

;***********************************************************

		#include <P16F747.INC>
		__CONFIG _CONFIG1, _FOSC_HS & _CP_OFF & _DEBUG_OFF & _VBOR_2_0 & _BOREN_0 & _MCLR_ON & _PWRTE_ON & _WDT_OFF
		__CONFIG _CONFIG2, _BORSEN_0 & _IESO_OFF & _FCMEN_OFF


; Variable declarations
A_sens	equ		20h						; Ambient Measurement 1
P_sens	equ		21h						; Plate Measurement 1
A_temp	equ		22h						; Ambient Measurment 2 / average of Ambient Measurement 1 and 2
P_temp	equ		23h						; Plate Mesurement 2 / average of Plate Measurement 1 and 2
Temp	equ		24h						; Temporary counter
P_BaseH	equ		25h						; Upper Hysteresis Set Point
P_BaseL	equ		26h						; Lower Hysteresis Set Point
A_Diff	equ		27h						; Ambient offset from 96 (23 degree C)
Flag	equ		28h						; Flag indicates whether to subtract or add A_Diff

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
		clrf 	PORTC 					; Clear Port C output latches
		clrf 	PORTD 					; Clear Port D output latches		
		bsf 	STATUS,RP0 				; Set bit in STATUS register for bank 1
		movlw 	h'0E'		 			; move hex value 0E into W register
		movwf 	TRISA 					; Configure Port A pins 1,2,3 as inputs
		movlw	h'20'					; move hex value 20 to W register
		movwf 	TRISC 					; Configure Port C pin 5 as input
		clrf 	TRISD 					; Configure Port D pin as all output
		clrf	TRISE					; Clear Port E
		bcf 	STATUS,RP0 				; Clear bit in STATUS register for bank 0
		bcf		STATUS,C				; Clear carry bit

		movlw	h'C0'					; binary 11000000
		movwf	PORTD					; turn off LEDs, heater, and fan

initAD

		bsf 	STATUS,RP0 				; select register bank 1
		movlw 	B'00011011' 			; set A/D port configuration bit AN3,AN2,AN1,AN0 as analog input
		movwf 	ADCON1 					; move to special function A/D register
		bcf 	STATUS,RP0 				; select register bank 0
		
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

;&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
;
; Main Control Loop

waitToggle

		btfsc	PORTC,5					; skip if low. switch is closed.
		goto	switchOn

switchOff

		movlw	h'C0'					; binary 11000000
		movwf	PORTD					; turn off LEDs, heater, and fan

		goto	waitToggle

switchOn

		btfsc	PORTC,5					; see if switch is still on. skip if low. switch is closed.
		goto	controlTemperature		; switch is open (high)

		goto	waitToggle


controlTemperature

;############################################################
; Read the Ambient Temperature twice from channel 1 and the 
; Plate Temperature twice from channel 2. Channel reading is
; alternated to give more time between sensor readings

		movlw 	B'01001001' 			; select 8 * oscillator, analog input 0, turn on Channel 01
		movwf 	ADCON0 					; move to special function A/D register
		
		bsf 	ADCON0,GO 				; start A/D conversion
		call	checkAD					; check if A/D conversion finished
		movwf	A_sens					; store A/D reading in A_sens

		movlw 	B'01010001' 			; select 8 * oscillator, analog input 0, turn on Channel 02
		movwf 	ADCON0 					; move to special function A/D register

		bsf 	ADCON0,GO 				; start A/D conversion
		call	checkAD					; check if A/D conversion is finished
		movwf	P_sens					; store A/D reading in P_sens

		movlw 	B'01001001' 			; select 8 * oscillator, analog input 0, turn on Channel 01
		movwf 	ADCON0 					; move to special function A/D register

		bsf 	ADCON0,GO 				; start A/D conversion
		call	checkAD					; check if A/D conversion is finished
		movwf	A_temp					; store A/D reading in A_temp
		
		movlw 	B'01010001' 			; select 8 * oscillator, analog input 0, turn on Channel 02
		movwf 	ADCON0 					; move to special function A/D register

		bsf 	ADCON0,GO 				; start A/D conversion
		call	checkAD					; check if A/D conversion is finished
		movwf	P_temp					; store A/D reading in P_temp


;############################################################
; Take the average between the 2 readings for the Ambient and 
; Plate Temperatures

		movf	A_sens,W				; move A_sense to W register
		addwf	A_temp,F				; add W register to A_temp
		rrf		A_temp,F				; divide A_temp by 2

		movf	P_sens,W				; move P_sense to W register
		addwf	P_temp,F				; add W register to P_temp
		rrf		P_temp,F				; divide P_temp by 2


;############################################################
; Find the difference between the Ambient temperature reading 
; and the base value of 96 (23 degree C)

		movlw	h'60'					; move value 96 (23 degree C for Amb Sensor)
		subwf	A_temp,W				; subtract W Register from A_temp, store in W register

		btfss	STATUS,C				; skip if C is set (if A_temp >= 96)
		bsf		Flag,0					; set Flag bit 0

		btfss	STATUS,C				; skip if C is set (if A_temp >= 96)
		movf	A_temp,W				; move A_temp to the W register
		btfss	STATUS,C				; skip if C is set (if A_temp >= 96)
		sublw	h'60'					; subtract W register from value 96
		
		movwf	A_Diff					; move W register to A_Diff
		bcf		STATUS,C				; clear carry bit
		rlf		A_Diff,F				; multiply A_Diff by 2


;############################################################
; Set the Upper and Lower Hysteresis Limits according to the 
; A_Diff calculated in the previous section and the base values 
; of 119 (78 degree C) and 97 (68 degree C)

		movf	A_Diff,W				; move A_Diff to W register
		btfss	Flag,0					; skip if Flag is set
		addlw	D'119'					; add literal 119 (78 degree C) to W register
		btfsc	Flag,0					; skip if Flag is clear
		sublw	D'119'					; subtract W register from literal 119 (78 degree C)
		movwf	P_BaseH					; move W register to P_BaseH

		
		movf	A_Diff,W
		btfss	Flag,0					; skip if Flag is set
		addlw	D'97'					; add W register to literal 97 (68 degree C)
		btfsc	Flag,0					; skip if Flag is clear
		sublw	D'97'					; subtract W register from literal 97 (68 degree C)
		movwf	P_BaseL					; move W Register to P_BaseL
	
	
;############################################################
; Check to see where the Plate temperature falls around the 
; Hysteresis Limits
		
		bcf		Flag,0					; clear Flag

		movf	P_temp,W				; move P_temp to W register
		subwf	P_BaseL,W				; P_BaseL - P_temp
		btfsc	STATUS,C				; skip if clear (P_temp > P_BaseL)
		goto	heatUp
		
		movf	P_temp,W				; move P_temp to W register
		subwf	P_BaseH,W				; P_BaseH - P_temp
		btfss	STATUS,C				; skip if set (P_temp <= P_BaseH)
		goto	coolDown

		bsf		PORTD,1					; indicate in range (Turn on Yellow)
		bcf		PORTD,0					; turn off LED 0
		bcf		PORTD,2					; turn off LED 2
	
		goto 	waitToggle


; end of controlTemperature
;############################################################

checkAD

		btfsc 	ADCON0,GO 				; check if A/D is finished
		goto 	checkAD			 		; loop right here until A/D finished
		btfsc 	ADCON0,GO 				; make sure A/D finished
		goto 	checkAD					; A/D not finished, continue to wait
		movf	ADRESH,W				; move ADRESH to W register
		return

heatUp

		bcf		PORTD,6					; turn on heater
		bsf		PORTD,7					; turn off fan

		bsf		PORTD,2					; indicate cold		
		bcf		PORTD,0					; turn off LED 0
		bcf		PORTD,1					; turn off LED 1
		
		goto	waitToggle

coolDown

		bsf		PORTD,6					; turn off heater
		bcf		PORTD,7					; turn on fan

		bsf		PORTD,0					; indicate hot
		bcf		PORTD,1					; turn off LED 0
		bcf		PORTD,2					; turn off LED 1

		goto	waitToggle

;
;&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&


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