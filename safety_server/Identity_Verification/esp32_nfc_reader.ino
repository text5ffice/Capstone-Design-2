/*
 * ===== ESP32 + RC522 NFC 신원확인 시스템 =====
 * 
 * [하드웨어 연결 (ESP32 ↔ RC522)]
 *   RC522 SDA  → ESP32 GPIO 5
 *   RC522 SCK  → ESP32 GPIO 18
 *   RC522 MOSI → ESP32 GPIO 23
 *   RC522 MISO → ESP32 GPIO 19
 *   RC522 RST  → ESP32 GPIO 27
 *   RC522 3.3V → ESP32 3.3V
 *   RC522 GND  → ESP32 GND
 * 
 * [하드웨어 연결 (ESP32 ↔ 부저/릴레이/LED)]
 *   녹색 LED   → GPIO 2  (+ 220Ω 저항)
 *   적색 LED   → GPIO 4  (+ 220Ω 저항)
 *   부저       → GPIO 15
 *   릴레이     → GPIO 13
 * 
 * [필요한 라이브러리 - Arduino IDE에서 설치]
 *   1. MFRC522 (by GithubCommunity)  → 라이브러리 매니저에서 검색
 *   2. ArduinoJson (by Benoit Blanchon) → 라이브러리 매니저에서 검색
 *   3. WiFi, HTTPClient → ESP32 보드 설치하면 자동으로 포함됨
 * 
 * [Arduino IDE 보드 설정]
 *   보드: ESP32 Dev Module
 *   Upload Speed: 115200
 *   Flash Frequency: 80MHz
 */

#include <SPI.h>
#include <MFRC522.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>

// ============ 여기만 수정하면 됨 ============
const char* WIFI_SSID     = "현장WiFi이름";      // 현장 WiFi 이름
const char* WIFI_PASSWORD  = "WiFi비밀번호";      // 현장 WiFi 비밀번호
const char* SERVER_URL     = "http://192.168.0.100:5000";  // Flask 서버 IP (노트북 IP)
const char* GATE_ID        = "GATE_A";            // 이 출입구의 고유 이름
// ==========================================

// RC522 핀 설정
#define SS_PIN   5    // SDA
#define RST_PIN  27   // RST

// 출력 핀 설정
#define GREEN_LED_PIN  2
#define RED_LED_PIN    4
#define BUZZER_PIN     15
#define RELAY_PIN      13

MFRC522 rfid(SS_PIN, RST_PIN);

// 실패 횟수 추적 (같은 카드가 연속 실패할 때 카운트)
String lastFailedUID = "";
int failCount = 0;

void setup() {
  Serial.begin(115200);
  
  // 핀 모드 설정
  pinMode(GREEN_LED_PIN, OUTPUT);
  pinMode(RED_LED_PIN, OUTPUT);
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(RELAY_PIN, OUTPUT);
  
  // 초기 상태: 모두 꺼짐
  digitalWrite(GREEN_LED_PIN, LOW);
  digitalWrite(RED_LED_PIN, LOW);
  digitalWrite(BUZZER_PIN, LOW);
  digitalWrite(RELAY_PIN, LOW);  // 릴레이 OFF = 출입 차단

  // SPI 및 RC522 초기화
  SPI.begin();
  rfid.PCD_Init();
  Serial.println("RC522 NFC 리더 초기화 완료!");
  
  // WiFi 연결
  connectWiFi();
  
  Serial.println("=== NFC 카드를 대주세요 ===");
}

void loop() {
  // 새 카드가 감지되지 않으면 대기
  if (!rfid.PICC_IsNewCardPresent()) return;
  if (!rfid.PICC_ReadCardSerial()) return;
  
  // 카드 UID 읽기 (예: "A3:B2:C1:D4")
  String uid = getCardUID();
  Serial.print("카드 감지! UID: ");
  Serial.println(uid);
  
  // 서버에 확인 요청
  int result = verifyWorker(uid);
  
  // 결과에 따라 동작
  if (result == 1) {
    // ====== 인증 성공 ======
    Serial.println("✅ 인증 성공!");
    handleSuccess();
    
    // 실패 카운트 초기화
    lastFailedUID = "";
    failCount = 0;
    
  } else {
    // ====== 인증 실패 ======
    // 같은 카드가 연속 실패하면 카운트 증가
    if (uid == lastFailedUID) {
      failCount++;
    } else {
      lastFailedUID = uid;
      failCount = 1;
    }
    
    Serial.print("❌ 인증 실패! (");
    Serial.print(failCount);
    Serial.println("회째)");
    
    if (failCount >= 3) {
      // 3회 이상 실패 → 최종 실패 (관리자 푸시 알림은 서버에서 처리)
      handleFinalFail();
    } else {
      // 1~2회 실패
      handleFail();
    }
  }
  
  // 카드 읽기 종료 (다음 카드 대기)
  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();
  
  delay(1500);  // 1.5초 대기 (중복 인식 방지)
}


// ============ 카드 UID 읽기 ============
String getCardUID() {
  String uid = "";
  for (byte i = 0; i < rfid.uid.size; i++) {
    if (i > 0) uid += ":";
    if (rfid.uid.uidByte[i] < 0x10) uid += "0";
    uid += String(rfid.uid.uidByte[i], HEX);
  }
  uid.toUpperCase();
  return uid;
}


// ============ 서버에 신원 확인 요청 ============
int verifyWorker(String uid) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi 연결 끊김! 재연결 시도...");
    connectWiFi();
  }
  
  HTTPClient http;
  String url = String(SERVER_URL) + "/api/verify";
  
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  
  // JSON 데이터 만들기
  // {"uid": "A3:B2:C1:D4", "gate_id": "GATE_A", "fail_count": 2}
  StaticJsonDocument<200> doc;
  doc["uid"] = uid;
  doc["gate_id"] = GATE_ID;
  doc["fail_count"] = failCount;
  
  String jsonStr;
  serializeJson(doc, jsonStr);
  
  Serial.print("서버 요청: ");
  Serial.println(jsonStr);
  
  // POST 요청 보내기
  int httpCode = http.POST(jsonStr);
  
  if (httpCode == 200) {
    String response = http.getString();
    Serial.print("서버 응답: ");
    Serial.println(response);
    
    // 응답 파싱
    StaticJsonDocument<512> resDoc;
    deserializeJson(resDoc, response);
    
    bool verified = resDoc["verified"];
    http.end();
    return verified ? 1 : 0;
    
  } else {
    Serial.print("서버 오류! HTTP 코드: ");
    Serial.println(httpCode);
    http.end();
    return -1;  // 서버 연결 실패
  }
}


// ============ 인증 성공 동작 ============
void handleSuccess() {
  // 녹색 LED ON
  digitalWrite(GREEN_LED_PIN, HIGH);
  // 릴레이 ON (출입 허용)
  digitalWrite(RELAY_PIN, HIGH);
  // 짧은 "삐" 소리 1회 (성공음)
  tone(BUZZER_PIN, 1000, 200);  // 1000Hz, 0.2초
  
  delay(3000);  // 3초간 출입 허용
  
  // 원래 상태로 복귀
  digitalWrite(GREEN_LED_PIN, LOW);
  digitalWrite(RELAY_PIN, LOW);
}


// ============ 인증 실패 동작 (1~2회) ============
void handleFail() {
  // 적색 LED ON
  digitalWrite(RED_LED_PIN, HIGH);
  // 릴레이 OFF 유지 (출입 차단)
  // "삐삐" 소리 2회 (실패음)
  for (int i = 0; i < 2; i++) {
    tone(BUZZER_PIN, 500, 300);  // 500Hz, 0.3초
    delay(400);
  }
  
  delay(1000);
  digitalWrite(RED_LED_PIN, LOW);
}


// ============ 최종 실패 동작 (3회 이상) ============
void handleFinalFail() {
  // 적색 LED ON
  digitalWrite(RED_LED_PIN, HIGH);
  // 경고음 "삐용삐용" 5회
  for (int i = 0; i < 5; i++) {
    tone(BUZZER_PIN, 800, 200);
    delay(250);
    tone(BUZZER_PIN, 400, 200);
    delay(250);
  }
  
  delay(1000);
  digitalWrite(RED_LED_PIN, LOW);
  
  // ※ 관리자 푸시 알림은 서버(Flask)에서 자동 발송됨
  //    fail_count >= 3이면 서버가 FCM으로 푸시 보냄
}


// ============ WiFi 연결 ============
void connectWiFi() {
  Serial.print("WiFi 연결 중...");
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500);
    Serial.print(".");
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println(" 연결됨!");
    Serial.print("IP 주소: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println(" 연결 실패!");
  }
}
