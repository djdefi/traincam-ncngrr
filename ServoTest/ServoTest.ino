// Single-servo hardware test for Inventr.io HERO (Arduino Uno compatible).
// Signal on D9, servo power from HERO 5V/GND.
// D9 confirmed by test to drive the PAN axis (left/right).
// Runs one conservative sweep, then leaves the servo centered.

#include <Servo.h>

const int SERVO_PIN = 9;
const int CENTER = 90;
const int STEP_DELAY_MS = 20;

Servo servo;
int currentAngle = CENTER;

void moveTo(int target) {
  Serial.print("Requested: ");
  Serial.println(target);

  int step = (target > currentAngle) ? 1 : -1;
  while (currentAngle != target) {
    currentAngle += step;
    servo.write(currentAngle);
    Serial.print("Current: ");
    Serial.println(currentAngle);
    delay(STEP_DELAY_MS);
  }
}

void setup() {
  Serial.begin(115200);

  servo.attach(SERVO_PIN);
  servo.write(CENTER);
  Serial.println("Centered at 90, holding 2s...");
  delay(2000);

  moveTo(70);
  delay(500);
  moveTo(90);
  delay(500);
  moveTo(110);
  delay(500);
  moveTo(90);

  Serial.println("Test complete. Servo centered at 90.");
}

void loop() {
  // Intentionally empty: no repeating sweep.
}
