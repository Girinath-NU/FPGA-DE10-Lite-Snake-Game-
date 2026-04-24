#define X_pin A0
#define Y_pin A1

// Digital output pins
#define NORTH_pin 2   // UP
#define SOUTH_pin 3   // DOWN
#define WEST_pin  4   // LEFT
#define EAST_pin  5   // RIGHT

int minThreshold = 300;
int maxThreshold = 700;

void setup() {
  pinMode(NORTH_pin, OUTPUT);
  pinMode(SOUTH_pin, OUTPUT);
  pinMode(WEST_pin, OUTPUT);
  pinMode(EAST_pin, OUTPUT);

  Serial.begin(115200);
}

void loop() {

  int xValue = analogRead(X_pin);
  int yValue = analogRead(Y_pin);

  // Reset all outputs
  digitalWrite(NORTH_pin, LOW);
  digitalWrite(SOUTH_pin, LOW);
  digitalWrite(WEST_pin, LOW);
  digitalWrite(EAST_pin, LOW);

  // Decide ONLY ONE direction (priority: vertical > horizontal)
  if (yValue > maxThreshold) {
    digitalWrite(NORTH_pin, HIGH);
  }
  else if (yValue < minThreshold) {
    digitalWrite(SOUTH_pin, HIGH);
  }
  else if (xValue > maxThreshold) {   // <-- swapped here
    digitalWrite(WEST_pin, HIGH);     // RIGHT becomes WEST
  }
  else if (xValue < minThreshold) {   // <-- swapped here
    digitalWrite(EAST_pin, HIGH);     // LEFT becomes EAST
  }

  // Debug
  Serial.print("X: ");
  Serial.print(xValue);
  Serial.print(" Y: ");
  Serial.print(yValue);
  Serial.print(" | N:");
  Serial.print(digitalRead(NORTH_pin));
  Serial.print(" S:");
  Serial.print(digitalRead(SOUTH_pin));
  Serial.print(" W:");
  Serial.print(digitalRead(WEST_pin));
  Serial.print(" E:");
  Serial.println(digitalRead(EAST_pin));

  delay(50);
}
