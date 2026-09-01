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
const unsigned long STEP_INTERVAL_MS = 15;  // pace of one-degree steps

Servo pan;
Servo tilt;
int panAngle = CENTER;
int tiltAngle = CENTER;
int panTarget = CENTER;
int tiltTarget = CENTER;
unsigned long lastStep = 0;

// One step toward the target. Never blocks, so a newer target set by the next
// serial command takes effect immediately instead of queueing behind this move.
void stepAxis(Servo &s, int &angle, int target) {
  target = constrain(target, MIN_ANGLE, MAX_ANGLE);  // belt and braces
  if (angle == target) {
    return;
  }
  angle += (target > angle) ? 1 : -1;
  s.write(angle);
}

void report() {
  Serial.print("P:");
  Serial.print(panTarget);
  Serial.print(" T:");
  Serial.println(tiltTarget);
}

void setup() {
  Serial.begin(115200);
  Serial.setTimeout(50);  // parseInt shouldn't stall the step loop
  pan.attach(PAN_PIN);
  tilt.attach(TILT_PIN);
  pan.write(panAngle);
  tilt.write(tiltAngle);
  Serial.println("READY");
  report();
}

void handleSerial() {
  if (!Serial.available()) {
    return;
  }

  char cmd = Serial.read();
  if (cmd == 'p' || cmd == 't') {
    // Read once into a local: constrain() is a macro and would evaluate a
    // Serial.parseInt() argument several times, draining the buffer to 0.
    int angle = Serial.parseInt();
    angle = constrain(angle, MIN_ANGLE, MAX_ANGLE);
    if (cmd == 'p') {
      panTarget = angle;
    } else {
      tiltTarget = angle;
    }
  } else if (cmd == 'c') {
    panTarget = CENTER;
    tiltTarget = CENTER;
  } else if (cmd == '?') {
    // fall through to report
  } else {
    return;  // ignore newlines and junk
  }

  report();
}

void loop() {
  handleSerial();

  if (millis() - lastStep >= STEP_INTERVAL_MS) {
    lastStep = millis();
    stepAxis(pan, panAngle, panTarget);
    stepAxis(tilt, tiltAngle, tiltTarget);
  }
}
