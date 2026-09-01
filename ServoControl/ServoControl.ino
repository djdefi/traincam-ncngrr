// Serial-controlled pan/tilt jog for Inventr.io HERO (Arduino Uno compatible).
// Driven by scripts/servo_web.py, which serves the browser UI and relays
// commands over USB serial.
//
//   D9  = PAN  (confirmed left/right by test)
//   D10 = TILT (confirmed up/down by test)
//
// Commands, one per line, 115200 baud:
//   p<angle>  move pan to angle      e.g. p110
//   t<angle>  move tilt to angle     e.g. t85
//   c         center both
//   ?         report current angles
//
// Angles are clamped to MIN_ANGLE..MAX_ANGLE so a typo can't drive a servo
// into its hard stop and stall it.

#include <Servo.h>

const int PAN_PIN = 9;
const int TILT_PIN = 10;
const int CENTER = 90;
const int MIN_ANGLE = 30;
const int MAX_ANGLE = 150;
const int STEP_DELAY_MS = 15;

Servo pan;
Servo tilt;
int panAngle = CENTER;
int tiltAngle = CENTER;

void moveTo(Servo &s, int &angle, int target) {
  target = constrain(target, MIN_ANGLE, MAX_ANGLE);
  int step = (target > angle) ? 1 : -1;
  while (angle != target) {
    angle += step;
    s.write(angle);
    delay(STEP_DELAY_MS);
  }
}

void report() {
  Serial.print("P:");
  Serial.print(panAngle);
  Serial.print(" T:");
  Serial.println(tiltAngle);
}

void setup() {
  Serial.begin(115200);
  pan.attach(PAN_PIN);
  tilt.attach(TILT_PIN);
  pan.write(panAngle);
  tilt.write(tiltAngle);
  Serial.println("READY");
  report();
}

void loop() {
  if (!Serial.available()) {
    return;
  }

  char cmd = Serial.read();
  if (cmd == 'p') {
    moveTo(pan, panAngle, Serial.parseInt());
  } else if (cmd == 't') {
    moveTo(tilt, tiltAngle, Serial.parseInt());
  } else if (cmd == 'c') {
    moveTo(pan, panAngle, CENTER);
    moveTo(tilt, tiltAngle, CENTER);
  } else if (cmd == '?') {
    // fall through to report
  } else {
    return;  // ignore newlines and junk
  }

  report();
}
