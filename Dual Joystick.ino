#define X1_pin A0
#define Y1_pin A1

#define X2_pin A2
#define Y2_pin A3

// Joystick 1
#define N1 2
#define S1 3
#define W1 4
#define E1 5

// Joystick 2
#define N2 6
#define S2 7
#define W2 8
#define E2 9

int minThreshold = 300;
int maxThreshold = 700;

void setup() {
  pinMode(N1, OUTPUT); pinMode(S1, OUTPUT);
  pinMode(W1, OUTPUT); pinMode(E1, OUTPUT);

  pinMode(N2, OUTPUT); pinMode(S2, OUTPUT);
  pinMode(W2, OUTPUT); pinMode(E2, OUTPUT);

  Serial.begin(115200);
}

void loop() {

  int x1 = analogRead(A0);
  int y1 = analogRead(A1);

  int x2 = analogRead(A2);
  int y2 = analogRead(A3);

  // Reset ALL outputs
  digitalWrite(N1, LOW); digitalWrite(S1, LOW);
  digitalWrite(W1, LOW); digitalWrite(E1, LOW);
  digitalWrite(N2, LOW); digitalWrite(S2, LOW);
  digitalWrite(W2, LOW); digitalWrite(E2, LOW);

  int j1[4] = {0,0,0,0}; // N S W E
  int j2[4] = {0,0,0,0};

  // ===== JOYSTICK 1 =====
  if (y1 > maxThreshold) { digitalWrite(N1, HIGH); j1[0]=1; }
  else if (y1 < minThreshold) { digitalWrite(S1, HIGH); j1[1]=1; }
  else if (x1 > maxThreshold) { digitalWrite(W1, HIGH); j1[2]=1; }
  else if (x1 < minThreshold) { digitalWrite(E1, HIGH); j1[3]=1; }

  // ===== JOYSTICK 2 =====
  if (y2 > maxThreshold) { digitalWrite(N2, HIGH); j2[0]=1; }
  else if (y2 < minThreshold) { digitalWrite(S2, HIGH); j2[1]=1; }
  else if (x2 > maxThreshold) { digitalWrite(W2, HIGH); j2[2]=1; }
  else if (x2 < minThreshold) { digitalWrite(E2, HIGH); j2[3]=1; }

  // ===== SERIAL DEBUG =====
  Serial.print("J1: ");
  for(int i=0;i<4;i++){ Serial.print(j1[i]); Serial.print(" "); }

  Serial.print("| J2: ");
  for(int i=0;i<4;i++){ Serial.print(j2[i]); Serial.print(" "); }

  Serial.println();

  delay(50);
}
