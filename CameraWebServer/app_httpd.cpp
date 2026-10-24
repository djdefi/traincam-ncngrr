#include "esp_http_server.h"
#include "esp_camera.h"
#include "img_converters.h"
#include <WiFi.h>

#if defined(ARDUINO_ARCH_ESP32) && defined(CONFIG_ARDUHAL_ESP_LOG)
#include "esp32-hal-log.h"
#endif

// Defined in CameraWebServer.ino, kept in RTC memory so they survive the
// reboots the WiFi recovery performs.
extern uint32_t bootCount;
extern uint32_t wifiRestartCount;
extern uint32_t batteryMillivolts;
extern float dieTemperatureC;

#define PART_BOUNDARY "123456789000000000000987654321"
static const char *_STREAM_CONTENT_TYPE = "multipart/x-mixed-replace;boundary=" PART_BOUNDARY;
static const char *_STREAM_BOUNDARY = "\r\n--" PART_BOUNDARY "\r\n";
static const char *_STREAM_PART = "Content-Type: image/jpeg\r\nContent-Length: %u\r\nX-Timestamp: %d.%06d\r\n\r\n";

httpd_handle_t stream_httpd = NULL;
// Second server, and not an optimisation. esp_http_server services every
// socket from ONE task, so the MJPEG handler below - which loops for as long
// as a viewer is watching - blocks every other request on its server for the
// whole session. Measured 2026-08-03: with a single browser tab streaming,
// /status, /control and a second /stream all timed out, indefinitely. Health
// checks have to answer while someone is watching, so control lives apart from
// video. This is the split Espressif's own CameraWebServer example uses (80 for
// control, 81 for stream) and that this sketch lost when it was trimmed down.
// ponytail: still ONE stream viewer at a time. Fixing that means a capture task
// feeding several sender tasks - real work, only worth it if the ESP32 stops
// being a second camera and starts serving the hall.
httpd_handle_t camera_httpd = NULL;

static esp_err_t stream_handler(httpd_req_t *req) {
  camera_fb_t *fb = NULL;
  struct timeval _timestamp;
  esp_err_t res = ESP_OK;
  size_t _jpg_buf_len = 0;
  uint8_t *_jpg_buf = NULL;
  char part_buf[128];

  res = httpd_resp_set_type(req, _STREAM_CONTENT_TYPE);
  if (res != ESP_OK) {
    return res;
  }

  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");

  while (true) {
    fb = esp_camera_fb_get();
    if (!fb) {
      log_e("Camera capture failed");
      res = ESP_FAIL;
    } else {
      _timestamp.tv_sec = fb->timestamp.tv_sec;
      _timestamp.tv_usec = fb->timestamp.tv_usec;

      if (fb->format != PIXFORMAT_JPEG) {
        bool jpeg_converted = frame2jpg(fb, 80, &_jpg_buf, &_jpg_buf_len);
        esp_camera_fb_return(fb);
        fb = NULL;
        if (!jpeg_converted) {
          log_e("JPEG compression failed");
          res = ESP_FAIL;
        }
      } else {
        _jpg_buf_len = fb->len;
        _jpg_buf = fb->buf;
      }
    }
    
    if (res == ESP_OK) {
      res = httpd_resp_send_chunk(req, _STREAM_BOUNDARY, strlen(_STREAM_BOUNDARY));
    }
    if (res == ESP_OK) {
      size_t hlen = snprintf((char *)part_buf, 128, _STREAM_PART, _jpg_buf_len, _timestamp.tv_sec, _timestamp.tv_usec);
      res = httpd_resp_send_chunk(req, (const char *)part_buf, hlen);
    }
    if (res == ESP_OK) {
      res = httpd_resp_send_chunk(req, (const char *)_jpg_buf, _jpg_buf_len);
    }
    if (fb) {
      esp_camera_fb_return(fb);
      fb = NULL;
      _jpg_buf = NULL;
    } else if (_jpg_buf) {
      free(_jpg_buf);
      _jpg_buf = NULL;
    }
    if (res != ESP_OK) {
      log_e("Send frame failed");
      break;
    }
  }

  return res;
}

static esp_err_t index_handler(httpd_req_t *req) {
  httpd_resp_set_status(req, "302 Found");
  httpd_resp_set_hdr(req, "Location", "/stream");
  return httpd_resp_send(req, NULL, 0);
}

// Health without pulling the video stream. In a train car there is no serial
// console and no display, so without this the only question you can answer is
// "is it up right now" - not "has it been rebooting all afternoon", which is
// exactly what the WiFi recovery above needs to be checked against.
static esp_err_t status_handler(httpd_req_t *req) {
  // Seeed moved the Sense module from OV2640 to OV3660 in 2025, and the two
  // need different tuning; this says which one is actually in the car.
  sensor_t *s = esp_camera_sensor_get();
  char buf[288];
  int len = snprintf(
    buf, sizeof(buf),
    "{\"uptime_s\":%lu,\"heap\":%lu,\"min_heap\":%lu,\"rssi\":%d,"
    "\"boots\":%lu,\"wifi_restarts\":%lu,\"battery_mv\":%lu,"
    "\"temperature_c\":%.1f,\"sensor_pid\":\"0x%x\"}",
    (unsigned long)(millis() / 1000), (unsigned long)ESP.getFreeHeap(),
    (unsigned long)ESP.getMinFreeHeap(), WiFi.RSSI(),
    (unsigned long)bootCount, (unsigned long)wifiRestartCount,
    (unsigned long)batteryMillivolts, dieTemperatureC,
    s ? (unsigned)s->id.PID : 0u);

  httpd_resp_set_type(req, "application/json");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  return httpd_resp_send(req, buf, len);
}

// Resolution and JPEG quality are the two knobs that decide whether this reads
// as a camera or as a 2003 webcam, and the right pair is a look-at-it-on-the-
// screen judgement, not a calculation - the light in a layout room is nothing
// like the light on a bench. Exposed at runtime because finding it through
// flash cycles is how the Pi's focus burned three sessions.
static esp_err_t control_handler(httpd_req_t *req) {
  sensor_t *s = esp_camera_sensor_get();
  if (!s) {
    return httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "no sensor");
  }

  // Exposure and colour, for a layout darker than the bench: measured
  // 2026-10-24, SVGA ran ~7fps indoors at 1.9Mbps, so the sensor's exposure,
  // not WiFi, sets the frame rate. Ranges are the esp32-camera sensor.h ones.
  struct Knob { const char *key; int lo, hi; int (*set)(sensor_t *, int); };
  static const Knob knobs[] = {
    {"gainceiling", 0, 6, [](sensor_t *s, int v) { return s->set_gainceiling(s, (gainceiling_t)v); }},
    {"aec2", 0, 1, [](sensor_t *s, int v) { return s->set_aec2(s, v); }},
    {"ae_level", -2, 2, [](sensor_t *s, int v) { return s->set_ae_level(s, v); }},
    {"aec", 0, 1, [](sensor_t *s, int v) { return s->set_exposure_ctrl(s, v); }},
    {"aec_value", 0, 1200, [](sensor_t *s, int v) { return s->set_aec_value(s, v); }},
    {"agc", 0, 1, [](sensor_t *s, int v) { return s->set_gain_ctrl(s, v); }},
    {"agc_gain", 0, 30, [](sensor_t *s, int v) { return s->set_agc_gain(s, v); }},
    {"brightness", -2, 2, [](sensor_t *s, int v) { return s->set_brightness(s, v); }},
    {"contrast", -2, 2, [](sensor_t *s, int v) { return s->set_contrast(s, v); }},
    {"saturation", -2, 2, [](sensor_t *s, int v) { return s->set_saturation(s, v); }},
    {"awb", 0, 1, [](sensor_t *s, int v) { return s->set_whitebal(s, v); }},
    {"awb_gain", 0, 1, [](sensor_t *s, int v) { return s->set_awb_gain(s, v); }},
    {"wb_mode", 0, 4, [](sensor_t *s, int v) { return s->set_wb_mode(s, v); }},
    {"lenc", 0, 1, [](sensor_t *s, int v) { return s->set_lenc(s, v); }},
    {"bpc", 0, 1, [](sensor_t *s, int v) { return s->set_bpc(s, v); }},
    {"wpc", 0, 1, [](sensor_t *s, int v) { return s->set_wpc(s, v); }},
  };

  char query[256];
  if (httpd_req_get_url_query_str(req, query, sizeof(query)) == ESP_OK) {
    char val[8];
    for (const Knob &k : knobs) {
      if (httpd_query_key_value(query, k.key, val, sizeof(val)) == ESP_OK) {
        int v = atoi(val);
        if (v >= k.lo && v <= k.hi) k.set(s, v);
      }
    }
    // Clamped, not trusted. set_framesize() indexes the sensor's resolution
    // table with this, so an out-of-range value reads off the end of it.
    if (httpd_query_key_value(query, "framesize", val, sizeof(val)) == ESP_OK) {
      int fs = atoi(val);
      if (fs >= 0 && fs <= FRAMESIZE_UXGA) s->set_framesize(s, (framesize_t)fs);
    }
    // 10 is the driver default; below 4 the encoder produces frames big enough
    // to starve PSRAM at high resolutions.
    if (httpd_query_key_value(query, "quality", val, sizeof(val)) == ESP_OK) {
      int q = atoi(val);
      if (q >= 4 && q <= 63) s->set_quality(s, q);
    }
  }

  // Echo what actually stuck, so a rejected value is visible rather than silent.
  const camera_status_t &c = s->status;
  char buf[384];
  int len = snprintf(buf, sizeof(buf),
    "{\"framesize\":%d,\"quality\":%d,\"gainceiling\":%d,\"aec2\":%d,"
    "\"ae_level\":%d,\"aec\":%d,\"aec_value\":%d,\"agc\":%d,\"agc_gain\":%d,"
    "\"brightness\":%d,\"contrast\":%d,\"saturation\":%d,\"awb\":%d,"
    "\"awb_gain\":%d,\"wb_mode\":%d,\"lenc\":%d,\"bpc\":%d,\"wpc\":%d}",
    (int)c.framesize, (int)c.quality, (int)c.gainceiling, (int)c.aec2,
    (int)c.ae_level, (int)c.aec, (int)c.aec_value, (int)c.agc, (int)c.agc_gain,
    (int)c.brightness, (int)c.contrast, (int)c.saturation, (int)c.awb,
    (int)c.awb_gain, (int)c.wb_mode, (int)c.lenc, (int)c.bpc, (int)c.wpc);
  httpd_resp_set_type(req, "application/json");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  return httpd_resp_send(req, buf, len);
}

void startCameraServer() {
  httpd_config_t config = HTTPD_DEFAULT_CONFIG();
  config.server_port = 80;
  config.ctrl_port = 32768;
  // A phone that wanders out of range mid-stream leaves its socket held open.
  // With a handful of sockets available, a few of those and the camera quietly
  // stops accepting new viewers - which at a fair looks like "it broke" and is
  // unfixable without a power cycle. LRU purge evicts the stalest connection
  // instead of refusing the new one.
  config.lru_purge_enable = true;

  httpd_uri_t index_uri = {
    .uri       = "/",
    .method    = HTTP_GET,
    .handler   = index_handler,
    .user_ctx  = NULL
  };

  httpd_uri_t stream_uri = {
    .uri       = "/stream",
    .method    = HTTP_GET,
    .handler   = stream_handler,
    .user_ctx  = NULL
  };

  httpd_uri_t status_uri = {
    .uri       = "/status",
    .method    = HTTP_GET,
    .handler   = status_handler,
    .user_ctx  = NULL
  };

  httpd_uri_t control_uri = {
    .uri       = "/control",
    .method    = HTTP_GET,
    .handler   = control_handler,
    .user_ctx  = NULL
  };

  log_i("Starting stream server on port: '%d'", config.server_port);
  if (httpd_start(&stream_httpd, &config) == ESP_OK) {
    httpd_register_uri_handler(stream_httpd, &index_uri);
    httpd_register_uri_handler(stream_httpd, &stream_uri);
  }

  // Diagnostics and tuning on their own server, so a viewer holding the stream
  // cannot silence them. /stream stays on 80 so every existing URL still works.
  httpd_config_t ctrl_config = HTTPD_DEFAULT_CONFIG();
  ctrl_config.server_port = 81;
  ctrl_config.ctrl_port = 32769;  // must differ from the stream server's
  ctrl_config.lru_purge_enable = true;

  log_i("Starting control server on port: '%d'", ctrl_config.server_port);
  if (httpd_start(&camera_httpd, &ctrl_config) == ESP_OK) {
    httpd_register_uri_handler(camera_httpd, &status_uri);
    httpd_register_uri_handler(camera_httpd, &control_uri);
  }
}
