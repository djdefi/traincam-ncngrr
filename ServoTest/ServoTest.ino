// Two-servo hardware test for Inventr.io HERO (Arduino Uno compatible).
// Servo power from HERO 5V/GND.
//   D9  = PAN  (confirmed left/right by test)
//   D10 = TILT (assumed - this test confirms it)
// Moves one axis at a time, then leaves both centered.

#include <Servo.h>

const int PAN_PIN = 9;
const int TILT_PIN = 10;
const int CENTER = 90;
const int STEP_DELAY_MS = 20;

Servo pan;
Servo tilt;

void sweep(Servo &s, int &angle, const char *name, int target) {
  Serial.print(name);
  Serial.print(" requested: ");
  Serial.println(target);

  int step = (target > angle) ? 1 : -1;
  while (angle != target) {
    angle += step;
    s.write(angle);
    Serial.print(name);
    Serial.print(" current: ");
    Serial.println(angle);
    delay(STEP_DELAY_MS);
  }
}

void setup() {
  Serial.begin(115200);

  int panAngle = CENTER;
  int tiltAngle = CENTER;

  pan.attach(PAN_PIN);
  tilt.attach(TILT_PIN);
  pan.write(CENTER);
  tilt.write(CENTER);
  Serial.println("Both centered at 90, holding 2s...");
  delay(2000);

  Serial.println("--- PAN (D9) ---");
  sweep(pan, panAngle, "PAN", 70);
  delay(500);
  sweep(pan, panAngle, "PAN", 110);
  delay(500);
  sweep(pan, panAngle, "PAN", 90);

  delay(1000);

  // Narrower range on the untested axis: tilt binds sooner and fights gravity.
  Serial.println("--- D10 (tilt?) ---");
  sweep(tilt, tiltAngle, "D10", 80);
  delay(500);
  sweep(tilt, tiltAngle, "D10", 100);
  delay(500);
  sweep(tilt, tiltAngle, "D10", 90);

  Serial.println("Test complete. Both centered at 90.");
}

void loop() {
  // Intentionally empty: no repeating sweep.
}
