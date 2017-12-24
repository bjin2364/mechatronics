#include <xc.h>
#include <pic.h>
	#pragma config FOSC=HS, CP=OFF, DEBUG=OFF, BORV=20, BOREN=0, MCLRE=ON, PWRTE=ON, WDTE=OFF
	#pragma config BORSEN=OFF, IESO=OFF, FCMEN=0
#define PORTBIT(adr,bit) ((unsigned)(&adr)*8+(bit))

//List of events
enum events
{
	GreenPress = 0,
	RedPress = 1,
};

enum events new_event;

	static bit greenButton @ PORTBIT(PORTC,0);	// Port for Green Button
	static bit redButton @ PORTBIT(PORTC,1);	// Port for Red Button
	static bit Uni_H @ PORTBIT(PORTB,4);		// Port for the horizontal unipolar interrupter
	static bit Uni_V @ PORTBIT(PORTB,5);		// Port for the vertical unipolar interrupter
	static bit Bi_H @ PORTBIT(PORTB,7);			// Port for the horizontal bipolar interrupter
	static bit Bi_V @ PORTBIT(PORTB,6);			// Port for the vertical bipolar interrupter

typedef unsigned char byte;

const int CW = 0;	// clockwise
const int CCW = 1;	// counter clockwise
const int H = 0;	// horizontal interrupter
const int V = 1;	// vertical interrupter

// Types of Rotation (for indexing rotateMotor matrix)
const int UniFull = 0;	// full step unipolar
const int BiFull = 1;	// full step bipolar
const int UniWave = 2;	// wave drive unipolar
const int BiWave = 3;	// wave drive bipolar

// Absolute position of unipolar and bipolar motors.
// Range from 0 to 3, which represents an index value of
// the rotateMotor matrix defined later
int u = 0;
int b = 0;

// bit masks for selecting different interrupters
const byte uniH = 0B00000001;
const byte uniV = 0B00000010;
const byte biV = 0B00000100;
const byte biH = 0B00001000;

byte UniInterrupter[2][2] = 
{
	{0B00000001,0B00000010},
	{0B00000001,0B00000010}
};

byte BiInterrupter[2][2] = 
{
	{0B00001000,0B00000100},
	{0B00001000,0B00000100}
};

// Matrix of Rotation sequences
// How it work: Select a row to indicate what type of rotation. Then step through
// each column from 0 to 3 to rotate clockwise, or step through the colums from 
// 3 to 0 to rotate counter clockwise. u and b determine which column to start.
byte rotateMotor[4][4] = 
{
	{0B10100011,0B10100110,0B10101100,0B10101001}, //Full: Uni-CW
	{0B00010000,0B01010000,0B01000000,0B00000000}, //Full: Bi-CW
	{0B10100001,0B10100010,0B10100100,0B10101000}, //Wave: Uni-CW
	{0B10010000,0B01100000,0B10000000,0B00100000}  //Wave: Bi-CW
};

// States
// Description: left character is the unipolar inerrupter, middle character is
// the bipolar interrupter, and right number is the mode. For example, HV1 is
// the state when the horizontal interrupter for the unipolar is high, the vertical
// interrupter for the bipolar is high, and it is Mode 1
enum states
{
	HH1 = 0,
	VH1 = 1,
	VV1 = 2,
	HV1 = 3, 
	HH2 = 4, 
	VH3 = 5, 
	HH4 = 6,
};

enum states currentState;

//Function declarations
void RotUniToV_CCW(void);
void RotUniToH_CW(void);
void RotBiToV_CW(void);
void RotBiToH_CCW(void);
void Rot90_Full(void);
void Rot270(void);
void Rot90_Wave(void);
void SwitchMode(void);
void Initialize(void);
void SwitchDelay(void);

// State Table
// matrix of function pointers that rotate the motor.
void (*state_table[7][2])(void) = 
{
	{SwitchMode,RotUniToV_CCW},
	{SwitchMode,RotBiToV_CW},
	{SwitchMode,RotUniToH_CW},
	{SwitchMode,RotBiToH_CCW},
	{SwitchMode,Rot90_Full},
	{SwitchMode,Rot270},
	{SwitchMode,Rot90_Wave},
};


void main (void)
{
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
// Port Peripheral Connections
// Port B - Lower 4 bits are connected to LEDs to indicate mode (outputs). Upper 4 bits are connected to optical interrupters (inputs)
// Port C - Green Pushbutton (bit 0) and Red Pushbutton (bit 1)
// Port D - Driver signals for the Unipolar (pins 0-3) and Bipolar (pins 4-7) Stepper Motors
// Port E - Octal Switch (bits 0-2)

	ADCON1 = 0B00001111;// Set all pins to digital
	PORTB = 0B00000000; // Clear Port B output latches
	PORTC = 0B00000000; // Clear Port C output latches
	PORTD = 0B00000000; // Clear Port D output latches
	PORTE = 0B00000000; // Clear Port E output latches	
	TRISB = 0B11110000; // Configure Port B as half output half input
	TRISC = 0B11111111; // Configure Port C as all input
	TRISD = 0B00000000; // Configure Port D as all output
	TRISE = 0B00000111; // Configure Port E as all input

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
	
	Initialize(); //synchronizes the motor and waits for the green button to be pressed

	while(1 != 2) // Infinite loop
	{
		if(greenButton == 1) 			// If green press...
		{
			while(greenButton == 1){} 	// Wait for release
			SwitchDelay(); 				// Let switch debounce
			new_event = GreenPress;		// set new_event

			(*state_table[currentState][new_event])();	// Run function in state table according to the indexes currentState and new_event
		}
		
		else if(redButton == 1) 		// If red press...
		{
			while(redButton == 1){} 	// Wait for release
			SwitchDelay(); 				// Let switch debounce
			new_event = RedPress;		// set new_event

			(*state_table[currentState][new_event])(); // Run function in state table according to the indexes currentState and new_event
		}		
	}
}

///////////////////////////////////////////////////////////////
//Functions
///////////////////////////////////////////////////////////////

void SwitchDelay (void) // Waits for switch debounce
{
	for (int i=200; i > 0; i--) {} // 1200 us delay
}

int StepDelay1(byte interrupter)
{ 
// Step delay between each step of the motor. 
// Input: 1 interrupter to detect 
// Output: return true if interrupter is detected, false if interrupter is not detected

	int flag = 0;
	for (int i = 0; i < 2000; i++)
	{
		//shift the PORTB register to the right 4 times to bring the interrupter values to
		//the first 4 bits. Then bitwise and the result with the variable "interrupter", which
		//is a bitmask of one of the 4 different interrupters 
		if ((PORTB >> 4) & interrupter){flag = 1;}
	}
	return flag;
}

int StepDelay2(byte interrupter1, byte interrupter2)
{
// Step delay between each step of the motor. 
// Input: 2 interrupters to detect 
// Output: return true if interrupter is detected, false if interrupter is not detected

	int flag = 0;
	for (int i = 0; i < 2000; i++)
	{
		// Similar to StepDelay1 except returns true if either interrupter 1 or interrupter2 are high
		if ((PORTB >> 4) & (interrupter1 + interrupter2)){flag = 1;}
	}
	return flag;
}

///////////////////////////////////
//Mode1 Functions
///////////////////////////////////

void RotUniToH_CW (void) // Rotate the unipolar to the horizontal position in the clockwise direction, full step
{
	int interrupterDetected = 0;
	
	while (1)
	{
		interrupterDetected = StepDelay1(uniH);	// check if Horizontal unipolar interrupter is detected
		if (interrupterDetected){break;}		// break if interrupter is detected

		// This sequence is for clockwise indexing (0 to 3)
		u++; 		// increment u	
		u = u%4;	// store new u value mod 4

		PORTD = rotateMotor[UniFull][u];	// rotate motor 1 step			
	}
	currentState = HV1;	// Set currentState
}

void RotUniToV_CCW (void) // Rotate the Unipolar to the vertical position in the counter clockwise direction, full step
{
	int interrupterDetected = 0;
	
	while (1)
	{
		interrupterDetected = StepDelay1(uniV); // check if Vertical unipolar interrupter is detected
		if (interrupterDetected){break;}		// break if interrupter is detected

		// This sequence is for counter clockwise indexing (3 to 0)
		u--;			// decrement u		
		u = (4+u)%4;	// store new u value. Adding 4 prevents mod 4 from returning negative value

		PORTD = rotateMotor[UniFull][u];				
	}
	currentState = VH1; // set currentState
}

void RotBiToV_CW (void) // Rotate the Bipolar to the vertical position in the clockwise direction, full step
{
	int interrupterDetected = 0;

	while (1)
	{
		interrupterDetected = StepDelay1(biV); // check if Vertical bipolar interrupter is detected
		if (interrupterDetected){break;}	   // break if interrupter is detected
		
		// clockwise indexing (0 to 3)
		b++;		// increment b
		b = b%4;	// store new b value mod 4

		PORTD = rotateMotor[BiFull][b];	// rotate motor 1 step
	}
	currentState = VV1; // set currentState
}

void RotBiToH_CCW (void) // Rotate the Bipolar to the horizontal position in the counter clockwise direction, full step
{
	int interrupterDetected = 0;

	while (1)
	{
		interrupterDetected = StepDelay1(biH);	// check if Horizontal bipolar interrupter is detected
		if (interrupterDetected){break;}		// break if interrupter is detected
		
		// counter clockwise indexing (3 to 0)
		b--;			// decrement b
		b = (4+b)%4;	// store new b value. Adding 4 prevents mod 4 fro returning negative value

		PORTD = rotateMotor[BiFull][b];	// rotate motor 1 step
	}
	currentState = HH1;	// set currentState
}


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// General Rotation Functions
// Note: these functions exist only for Modes 2 - 4, which require one of the motors to catch up to the other motor.
//		 Some of these functions could have been combined to save lines, but it would have decreased the speed of the
//		 overall program.
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

void RotUniTo (int pos,int dir)	
{
// Rotate the Unipolar to the specified position "pos" and in the specified direction "dir", full step
// Inputs: interrpter position (H or V), direction (CW or CCW)

	int interrupterDetected = 0;
	
	if (dir == CCW)	//rotate counter-clockwise
	{
		while (1)
		{
			//counter-clockwise indexing
			u--;
			u = (4+u)%4;

			PORTD = rotateMotor[UniFull][u]; // rotate motor 1 step

			interrupterDetected = StepDelay1(UniInterrupter[dir][pos]);	//check if interrupter (specified by "pos" input) is detected
			if (interrupterDetected & pos == H){break;}					// break if interrupter is detected
			if (interrupterDetected & pos == V){break;} 				// break if interrupter is detected								
		}
	}
	else	// rotate clockwise
	{
		while (1)
		{
			//clockwise indexing
			u++;
			u = u%4;
			PORTD = rotateMotor[UniFull][u];

			interrupterDetected = StepDelay1(UniInterrupter[dir][pos]);	// check if interrupter (specified by "pos" input) is detected
			if (interrupterDetected & pos == H){break;}					// break if interrupter is detected
			if (interrupterDetected & pos == V){break;}					// break if interrupter is detected				
		}
	}
}

void Wave_RotUniTo (int pos,int dir) 
{
// Same as RotateUniTo function, except wave drive
// Inputs: interrpter position (H or V), direction (CW or CCW)

	int interrupterDetected = 0;
	
	if (dir == CCW)	// rotate counter-clockwise
	{
		while (1)
		{
			// counter-clockwise indexing (3 to 0)
			u--;
			u = (4+u)%4;

			PORTD = rotateMotor[UniWave][u]; // rotate motor 1 step

			interrupterDetected = StepDelay1(UniInterrupter[dir][pos]);	// check if interrupter (specified by "pos" input) is detected
			if (interrupterDetected & pos == H){break;}					// break if interrupter is detected
			if (interrupterDetected & pos == V){break;}					// break if interrupter is detected				
		}
	}
	else	// rotate clockwise
	{
		while (1)
		{
			// clockwise indexing (0 to 3)
			u++;
			u = u%4;

			PORTD = rotateMotor[UniWave][u]; // rotate motor 1 step

			interrupterDetected = StepDelay1(UniInterrupter[dir][pos]);	// check if interrupter (specified by "pos" input) is detected
			if (interrupterDetected && pos == V){break;}				// break if interrupter is detected
			if (interrupterDetected && pos == H){break;}				// break if interrupter is detected					
		}
	}
}

void RotBiTo (int pos,int dir) 
{
// Rotate the Bipolar to the specified position "pos" in the specified direction "dir", full step
// Inputs: interrpter position (H or V), direction (CW or CCW)

	int interrupterDetected = 0;

	if (dir == CCW)	// rotate counter-clockwise
	{
		while (1)
		{
			// counter-clockwise indexing (3 to 0)
			b--;
			b = (4+b)%4;

			PORTD = rotateMotor[BiFull][b]; // rotate motor 1 step
	
			interrupterDetected = StepDelay1(BiInterrupter[dir][pos]);	// check if interrupter (specified by "pos" input) is detected
			if (interrupterDetected & pos == H){break;}					// break if interrupter is detected
			if (interrupterDetected & pos == V){break;}					// break if interrupter is detected	
		}
	}
	else	// rotate clockwise
	{
		while (1)
		{
			// clockwise indexing (0 to 3)
			b++;
			b = b%4;

			PORTD = rotateMotor[BiFull][b];	// rotate motor 1 step

			interrupterDetected = StepDelay1(BiInterrupter[dir][pos]);	// check if interrupter (specified by "pos" input) is detected
			if (interrupterDetected & pos == H){break;}					// break if interrupter is detected
			if (interrupterDetected & pos == V){break;}					// break if interrupter is detected	
		}
	}
}

void Wave_RotBiTo (char pos,int dir)	
{
// Same as RotBiTo function except wave drive
// Inputs: interrpter position (H or V), direction (CW or CCW)

	int interrupterDetected = 0;

	if (dir == CCW)	// rotate counter-clockwise
	{
		while (1)
		{
			// counter-clockwise indexing (3 to 0)
			b--;
			b = (b+4)%4;

			PORTD = rotateMotor[BiWave][b];	// rotate motor 1 step

			interrupterDetected = StepDelay1(BiInterrupter[dir][pos]);	// check if interrupter (specified by "pos" input) is detected
			if (interrupterDetected & pos == H){break;}					// break if interrupter is detected
			if (interrupterDetected & pos == V){break;}					// break if interrupter is detected
		}
	}
	else	// rotate clockwise
	{
		while (1)
		{
			// clockwise indexing
			b++;
			b = b%4;

			PORTD = rotateMotor[BiWave][b];	// rotate motor 1 step
	
			interrupterDetected = StepDelay1(BiInterrupter[dir][pos]);	// check if interrupter (specified by "pos" input) is detected
			if (interrupterDetected & pos == H){break;}					// break if interrupter is detected
			if (interrupterDetected & pos == V){break;}					// break if interrupter is detected			
		}	
	}
}

/////////////////////////////////////////////////////////////////////////////////////////////////////
//Mode2 Function
//Rotates both motors simultaneously 90 degrees to the next interrupter in full step
/////////////////////////////////////////////////////////////////////////////////////////////////////
void Rot90_Full(void)	
{
	int interrupterDetected = 0;

	while (1)
	{
		//Rotate to both motors to Vertical Position
		while (1)
		{
			interrupterDetected = StepDelay2(uniV,biV);	// check if Vertical unipolar interrupter or Vertical bipolar interrupter is detected
			if (interrupterDetected){break;}			// break if interrupter is detected

			// counter-clockwise indexing for u (3 to 0)
			// clockwise indexing for b (0 to 3)
			u--;
			u = (4+u)%4;
			b++;
			b = b%4;

			// Rotates both motors simultaneously
			// How it works: uses bitwise "and" operator to isolate the first 4 bits (unipolar) or last 4 bits (bipolar) of PORTD,
			// then sums the result and writes the new byte to PORTD   
			PORTD = ((rotateMotor[UniFull][u] & 0B00001111) + (rotateMotor[BiFull][b] & 0B11110000));				
		}

		if (Uni_V && !Bi_V){RotBiTo(V,CW);}		// If the unipolar reaches the interrupter first, rotate only the bipolar
		if (Bi_V && !Uni_V){RotUniTo(V,CCW);}	// If the bipolar reaches the interrupter first, rotate only the unipolar

		interrupterDetected = 0;	// reset interrupter flag

		//Rotate to both motors to Horizontal Position
		while (1)
		{
			interrupterDetected = StepDelay2(uniH,biH);	// check if Horizontal unipolar interrupter or Horizontal bipolar interrupter is detected
			if (interrupterDetected){break;}			// break if interrupter is detected

			// clockwise indexing for u (0 to 3)
			// counter-clockwise indexing for b (3 to 0)
			u++;
			u = u%4;
			b--;
			b = (4+b)%4;
			
			// Rotates both motors simultaneously
			// How it works: uses bitwise "and" operator to isolate the first 4 bits (unipolar) or last 4 bits (bipolar) of PORTD,
			// then sums the result and writes the new byte to PORTD 
			PORTD = ((rotateMotor[UniFull][u] & 0B00001111) + (rotateMotor[BiFull][b] & 0B11110000));				
		}

		if (Uni_H && !Bi_H){RotBiTo(H,CCW);}	// If the unipolar reaches the interrupter first, rotate only the bipolar	
		if (Bi_H && !Uni_H){RotUniTo(H,CW);}	// If the bipolar reaches the interrupter first, rotate only the unipolar

		if (redButton == 1){if (redButton == 1){break;}}	// break if red button is pressed. Also checks for noise
	}
	while(redButton == 1){}	// wait for red button to be released

	currentState = HH2;	// set currentState
}

/////////////////////////////////////////////////////////////////////////////////////////////
//Mode3 Function
//Rotates both motors simultaneously 270 degrees to the next interrupter in full step
/////////////////////////////////////////////////////////////////////////////////////////////
void Rot270(void)
{
	int interrupterDetected = 0;

	while(1)
	{
		//Rotate both motors counter-clockwise
		while (1)
		{
			interrupterDetected = StepDelay2(uniH,biV);	// check if Horizontal unipolar interrupter or Vertical bipolar interrupter is detected
			if (interrupterDetected){break;}			// break if interrupter is detected

			// counter-clockwise indexing for u (3 to 0)
			// counter-clockwise indexing for b (3 to 0)
			u--;
			u = (4+u)%4;
			b--;
			b = (4+b)%4;

			// Rotates both motors simultaneously
			// How it works: uses bitwise "and" operator to isolate the first 4 bits (unipolar) or last 4 bits (bipolar) of PORTD,
			// then sums the result and writes the new byte to PORTD 
			PORTD = ((rotateMotor[UniFull][u] & 0B00001111) + (rotateMotor[BiFull][b] & 0B11110000));
		}		
	
		if (Uni_H && !Bi_V){RotBiTo(V,CCW);}	// If the unipolar reaches the interrupter first, rotate only the bipolar
		if (Bi_V && !Uni_H){RotUniTo(H,CCW);}	// If the bipolar reaches the interrupter first, rotate only the unipolar

		interrupterDetected = 0;	// reset the interrupter flag

		//Rotate both motors clockwise
		while (1)
		{
			interrupterDetected = StepDelay2(uniV,biH);	// check if Vertical unipolar interrupter or Horizontal bipolar interrupter is detected
			if (interrupterDetected){break;}			// break if interrupter is detected

			// clockwise indexing for u (0 to 3)
			// clockwise indexing for b (0 to 3)
			u++;
			u = u%4;
			b++;
			b = b%4;

			// Rotates both motors simultaneously
			// How it works: uses bitwise "and" operator to isolate the first 4 bits (unipolar) or last 4 bits (bipolar) of PORTD,
			// then sums the result and writes the new byte to PORTD 
			PORTD = ((rotateMotor[UniFull][u] & 0B00001111) + (rotateMotor[BiFull][b] & 0B11110000));		
		}
	
		if (Uni_V && !Bi_H){RotBiTo(H,CW);}		// check if Vertical unipolar interrupter or Horizontal bipolar interrupter is detected
		if (Bi_H && !Uni_V){RotUniTo(V,CW);}	// If the bipolar reaches the interrupter first, rotate only the unipolar

		if (redButton == 1){if (redButton == 1){break;}}	// break if red button is pressed. Also checks for noise
	}
	while(redButton == 1){}	// wait for red button to be released

	currentState = VH3;	// set currentState
}

////////////////////////////////////////////////////////////////////////////////////////////////
//Mode4 Function
//Rotates both motors simultaneously 90 degrees to the next interrupter in wave drive
////////////////////////////////////////////////////////////////////////////////////////////////
void Rot90_Wave(void)
{
	int interrupterDetected = 0;

	while(1)
	{
		// Rotate both motors to Vertical Position
		while (1)
		{
			interrupterDetected = StepDelay2(uniV,biV);	// check if Vertical unipolar interrupter or Vertical bipolar interrupter is detected
			if (interrupterDetected){break;}			// break if interrupter is detected

			// counter-clockwise indexing for u (3 to 0)
			// clockwise indexing for b (0 to 3)
			u--;
			u = (4+u)%4;
			b++;
			b = b%4;

			// Rotates both motors simultaneously
			// How it works: uses bitwise "and" operator to isolate the first 4 bits (unipolar) or last 4 bits (bipolar) of PORTD,
			// then sums the result and writes the new byte to PORTD
			PORTD = ((rotateMotor[UniWave][u] & 0B00001111) + (rotateMotor[BiWave][b] & 0B11110000));		
		}	

		if (Uni_V && !Bi_V){Wave_RotBiTo(V,CW);}	// If the unipolar reaches the interrupter first, rotate only the bipolar
		if (Bi_V && !Uni_V){Wave_RotUniTo(V,CCW);}	// If the bipolar reaches the interrupter first, rotate only the unipolar

		interrupterDetected = 0;	// reset the interrupter flag

		// Rotate both motors to Horizontal Position
		while (1)
		{
			interrupterDetected = StepDelay2(uniH,biH);	// check if Horizontal unipolar interrupter or Horizontal bipolar interrupter is detected
			if (interrupterDetected){break;}			// break if interrupter is detected
			
			// clockwise indexing for u (0 to 3)
			// counter-clockwise indexing for b (3 to 0)
			u++;
			u = u%4;
			b--;
			b = (4+b)%4;

			// Rotates both motors simultaneously
			// How it works: uses bitwise "and" operator to isolate the first 4 bits (unipolar) or last 4 bits (bipolar) of PORTD,
			// then sums the result and writes the new byte to PORTD
			PORTD = ((rotateMotor[UniWave][u] & 0B00001111) + (rotateMotor[BiWave][b] & 0B11110000));
		}	

		if (Uni_H && !Bi_H){Wave_RotBiTo(H,CCW);}	// If the unipolar reaches the interrupter first, rotate only the bipolar
		if (Bi_H && !Uni_H){Wave_RotUniTo(H,CW);}	// If the bipolar reaches the interrupter first, rotate only the unipolar

		if (redButton == 1){if (redButton == 1){break;}}	// break if red button is pressed. Also checks for noise
	}
	while(redButton == 1){}	// wait for red button to be released

	currentState = HH4;	// set the currentState
}

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

void Synchronize (void) // Synchronize the motors
{
	RotUniToH_CW();					// Rotate the unipolar to the horizontal interrupter clockwise
	if (Bi_H == 0){RotBiTo(H,CW);}	// If the bipolar is not at the horizontal horizontal interrupter, rotate the bipolar to the horizontal interrupter clockwise
}

void HomeMode3(void) // Brings motors to home position for Mode 3
{
	int interrupterDetected = 0;

	//Rotate Back
	while (1)
	{
		interrupterDetected = StepDelay2(uniV,biH);	// check if Vertical unipolar interrupter or Horizontal bipolar interrupter is detected
		if (interrupterDetected){break;}			// break if the interrupter is detected

		// counter-clockwise indexing for u (3 to 0)
		// clockwise indexing for b (0 to 3)
		u--;
		u = (4+u)%4;
		b++;
		b = b%4;

		//Rotates both motors simultaneously
		//How it works: uses bitwise "and" operator to isolate the first 4 bits (unipolar) or last 4 bits (bipolar) of PORTD,
		//then sums the result and writes the new byte to PORTD
		PORTD = ((rotateMotor[UniFull][u] & 0B00001111) + (rotateMotor[BiFull][b] & 0B11110000));		
	}
	
	if (Uni_V && !Bi_H){RotBiTo(H,CW);}		// If the unipolar reaches the interrupter first, rotate only the bipolar
	if (Bi_H && !Uni_V){RotUniTo(V,CW);}	// If the bipolar reaches the interrupter first, rotate only the unipolar
}

void SwitchMode (void) // Switches between modes
{
	if (RE0 == 0 && RE1 == 1 && RE2 == 1)	// check octal switch (Mode1)
	{
		PORTB = 0B00000001;		// turn on LEDs
		Synchronize();			// rotate motors to home
		currentState = HH1;		// set the state
	}
	else if (RE0 == 1 && RE1 == 0 && RE2 == 1)	// check the octal switch (Mode2)
	{
		PORTB = 0B00000010;		// turn on the LEDs
		Synchronize();			// rotate motors to home
		currentState = HH2;		// set the state
	}
	else if (RE0 == 0 && RE1 == 0 && RE2 == 1)	// check the octal switch (Mode3)
	{
		PORTB = 0B00000011;		// turn on the LEDs
		HomeMode3();			// rotate motors to homs
		currentState = VH3;		// set the state
	}
	else if (RE0 == 1 && RE1 == 1 && RE2 == 0)	// check the octal swithc (Mode4)
	{
		PORTB = 0B00000100;		// turn on the LEDS
		Synchronize();			// rotate motors to home
		currentState = HH4;		// set the state
	}
	else						// If none of the modes are detected, fault
	{
		PORTB = 0B00001000;		// turn on fault LED
		while(1){};				// infinite while loop
	}
}

void Initialize(void) // Synchronizes the motors and waits for the green button to be pressed
{
	Synchronize();		// synchronize the motor

	while (1)
	{
		if(greenButton == 1)			// wait for green button to be pressed
		{
			while(greenButton == 1){}	// wait for green button to be released
			SwitchDelay();				// wait for switch to debounch
			if (RE0 == 0 && RE1 == 1 && RE2 == 1)		// check octal switch (Mode1)	
			{
				PORTB = 0B00000001;		// turn on LEDs
				currentState = HH1;		// set the state
				break;
			}
			else if (RE0 == 1 && RE1 == 0 && RE2 == 1)	// check octal switch (Mode2)
			{
				PORTB = 0B00000010;		// turn on LEDs
				currentState = HH2;		// set the state
				break;
			}
			else if (RE0 == 0 && RE1 == 0 && RE2 == 1)	// check the octal switch (Mode3)
			{
				PORTB = 0B00000011;		// turn on LEDS
				currentState = VH3;		// set the state
				break;
			}
			else if (RE0 == 1 && RE1 == 1 && RE2 == 0)	// check the octal switch (Mode4)
			{
				PORTB = 0B00000100;		// turn on LEDS
				currentState = HH4;		// set the state
				break;
			}
			else	// if none of the modes are detected, fault
			{
				PORTB = 0B00001000;		// turn on fault LED
				while(1){};				// wait in infinite loop
			}
		}
	}
}