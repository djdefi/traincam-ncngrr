#include "esp_camera.h"
#include <ESPmDNS.h>
#include <WiFi.h>
#include <esp_task_wdt.h>
#include <esp_wifi.h>

#define CAMERA_MODEL_XIAO_ESP32S3 // Has PSRAM

#include "camera_pins.h"
#include "app_httpd.h"

// ===========================
// WiFi Configuration
// ===========================
// Credentials live in secrets.h, which is gitignored. Copy secrets.h.example
// to secrets.h and fill it in. This repo is PUBLIC, and the password that used
// to sit here in plain text is still in git history as a result.
#include "secrets.h"

const char* ssid = TRAINCAM_WIFI_SSID;
const char* password = TRAINCAM_WIFI_PASSWORD;

// At a fair everything is switched on at once, so the access point is often not
// up yet when this board boots. Give it a bounded wait, then reboot and try
// again, instead of blocking in setup() forever.
static const uint32_t WIFI_CONNECT_TIMEOUT_MS = 30000;
// How long the link may stay down while running before we give up on it.
static const uint32_t WIFI_GRACE_MS = 30000;
static const uint32_t WDT_TIMEOUT_MS = 60000;

// RTC memory survives a soft reset but not a power cycle, which is exactly the
// scope we want: "how much has this board struggled since someone plugged it
// in". Without these the only way to know it had been rebooting all afternoon
// would be to notice the stream blink, and nobody is watching for that.
RTC_DATA_ATTR uint32_t bootCount = 0;
RTC_DATA_ATTR uint32_t wifiRestartCount = 0;

// Last time the link was seen up. Not in RTC memory: it is meaningless across a
// reboot, and a stale value would trigger an immediate second restart.
static uint32_t lastConnectedMs = 0;

// Bounded connect. Returns false rather than blocking, so every caller has to
// decide what to do about failure.
static bool connectWiFi(uint32_t timeoutMs) {
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);        // power save wakes badly under load; we are not on a coin cell
  WiFi.setAutoReconnect(true); // lets brief drops heal without a reboot
  WiFi.begin(ssid, password);

  const uint32_t start = millis();
  while (WiFi.status() != WL_CONNECTED) {
    // Unsigned subtraction, so this stays correct across the ~49 day millis()
    // rollover. Do not "fix" it to millis() > start + timeoutMs.
    if (millis() - start > timeoutMs) {
      return false;
    }
    delay(250);
    esp_task_wdt_reset();
  }
  // setSleep(false) above maps to WIFI_PS_NONE, but it is applied before the
  // station has associated and the connect can put power save back. Modem sleep
  // parks the radio between DTIM beacons, which shows up as latency spikes on a
  // stream. Re-assert it here, after association, where it sticks.
  esp_wifi_set_ps(WIFI_PS_NONE);
  return true;
}

void setup() {
  // Serial was previously guarded by `if (Serial)` BEFORE Serial.begin(), so on
  // a board with native USB CDC it could skip init entirely - and then the
  // camera failure message below printed nowhere. On a device with no display
  // that is the only diagnostic channel there is.
  Serial.begin(115200);
  Serial.setDebugOutput(true);
  Serial.println();

  bootCount++;

  // Core 3.x already starts the task WDT, so init returns INVALID_STATE and we
  // reconfigure instead. Guards against a hang anywhere in the loop task.
  esp_task_wdt_config_t wdtConfig = {
    .timeout_ms = WDT_TIMEOUT_MS,
    .idle_core_mask = 0,
    .trigger_panic = true,
  };
  if (esp_task_wdt_init(&wdtConfig) == ESP_ERR_INVALID_STATE) {
    esp_task_wdt_reconfigure(&wdtConfig);
  }
  esp_task_wdt_add(NULL);  // already-added returns INVALID_ARG, which is harmless

  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  // 24MHz, not the stock 20MHz. The S3's LCD_CAM peripheral generates XCLK
  // internally rather than through LEDC, so the higher rate is available and
  // lifts the OV2640's own ceiling (25->30fps at VGA/SVGA per mjpeg2sd's
  // README). Watch for colour artifacts if quality is ever pushed below ~10.
  config.xclk_freq_hz = 24000000;
  config.frame_size = FRAMESIZE_UXGA;
  config.pixel_format = PIXFORMAT_JPEG; // for streaming
  config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;
  config.fb_location = CAMERA_FB_IN_PSRAM;
  config.jpeg_quality = 12;
  config.fb_count = 1;
  
  // if PSRAM IC present, init with UXGA resolution and higher JPEG quality
  //                      for larger pre-allocated frame buffer.
  if(config.pixel_format == PIXFORMAT_JPEG){
    if(psramFound()){
      config.jpeg_quality = 10;
      config.fb_count = 2;
      config.grab_mode = CAMERA_GRAB_LATEST;
    } else {
      // Limit the frame size when PSRAM is not available
      config.frame_size = FRAMESIZE_SVGA;
      config.fb_location = CAMERA_FB_IN_DRAM;
    }
  } else {
    // Optimized for streaming performance
    config.frame_size = FRAMESIZE_240X240;
#if CONFIG_IDF_TARGET_ESP32S3
    config.fb_count = 2;
#endif
  }

  // camera init
  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("Camera init failed with error 0x%x", err);
    delay(5000);
    ESP.restart();
    return;
  }

  sensor_t * s = esp_camera_sensor_get();
  // initial sensors are flipped vertically and colors are a bit saturated
  if (s->id.PID == OV3660_PID) {
    s->set_vflip(s, 1); // flip it back
    s->set_brightness(s, 1); // up the brightness just a bit
    s->set_saturation(s, -2); // lower the saturation
  }
  // The stock sketch drops to QVGA here "for higher initial frame rate". On a
  // kiosk monitor that reads as a broken camera: 320x240 at ~3.6KB a frame,
  // stretched to full screen. Measured 2026-08-03 with the board in hand.
  // SVGA is the starting point, not the answer - tune it live against
  // /control?framesize=N&quality=N and set whatever wins here.
  if(config.pixel_format == PIXFORMAT_JPEG){
    s->set_framesize(s, FRAMESIZE_SVGA);
  }

  if (!connectWiFi(WIFI_CONNECT_TIMEOUT_MS)) {
    Serial.println("WiFi did not come up; rebooting to retry");
    wifiRestartCount++;
    ESP.restart();
  }
  Serial.println("");
  Serial.println("WiFi connected");
  lastConnectedMs = millis();

  char hostname[24];
  snprintf(hostname, sizeof(hostname), "traincam-%06llx",
           static_cast<unsigned long long>((ESP.getEfuseMac() >> 24) & 0xFFFFFF));
  if (MDNS.begin(hostname)) {
    MDNS.addService("http", "tcp", 80);
    MDNS.addService("traincam", "tcp", 80);
    MDNS.addServiceTxt("traincam", "tcp", "type", "esp32");
    MDNS.addServiceTxt("traincam", "tcp", "stream", "mjpeg");
    MDNS.addServiceTxt("traincam", "tcp", "control", "81");
  } else {
    Serial.println("mDNS setup failed; IP access remains available");
  }

  startCameraServer();

  Serial.printf("Camera ready: http://%s.local/stream\n", hostname);
  Serial.printf("Health/tuning: http://%s.local:81/status  :81/control\n", hostname);
}

void loop() {
  esp_task_wdt_reset();

  if (WiFi.status() == WL_CONNECTED) {
    lastConnectedMs = millis();
  } else if (millis() - lastConnectedMs > WIFI_GRACE_MS) {
    // ponytail: reboot rather than reconnect in place. mDNS does not reliably
    // re-advertise after a reconnect, and httpd is left holding sockets for
    // clients that are already gone, so a live reconnect tends to come back
    // unreachable by name. A reboot is about a second and returns the whole
    // board to a known state. Upgrade to in-place recovery only if that second
    // of downtime ever turns out to matter.
    Serial.println("WiFi down past the grace period; rebooting");
    wifiRestartCount++;
    ESP.restart();
  }

  delay(1000);
}
