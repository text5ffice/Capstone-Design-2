"""
===== NFC 신원확인 Flask 서버 =====

[실행 환경]
  Python 3.8 이상, 노트북 또는 라즈베리파이

[설치 명령어 - 터미널에서 한 번만 실행]
  pip install flask flask-cors pymysql firebase-admin

[실행 방법]
  python app.py

[MySQL 먼저 설치 & 실행 필요]
  1. MySQL 설치 (https://dev.mysql.com/downloads/)
  2. MySQL에서 아래 SQL 실행 (schema.sql 파일 참고)
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
import pymysql
from datetime import datetime, timedelta
import json

# ─── Firebase 푸시 알림 (선택사항, 나중에 설정) ───
# import firebase_admin
# from firebase_admin import credentials, messaging
# cred = credentials.Certificate("firebase-key.json")
# firebase_admin.initialize_app(cred)

app = Flask(__name__)
CORS(app)  # Flutter 앱에서 접근 허용


# ============ 여기만 수정하면 됨 ============
DB_CONFIG = {
    "host": "localhost",      # MySQL 서버 주소
    "user": "root",           # MySQL 사용자
    "password": "admin",       # MySQL 비밀번호
    "database": "safety_db",  # 데이터베이스 이름
    "charset": "utf8mb4",
}
# ==========================================


def get_db():
    """MySQL 연결 생성"""
    return pymysql.connect(**DB_CONFIG, cursorclass=pymysql.cursors.DictCursor)


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# API 1: NFC 신원확인 (ESP32가 호출)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
@app.route("/api/verify", methods=["POST"])
def verify_worker():
    """
    ESP32에서 보내는 데이터:
    {
        "uid": "A3:B2:C1:D4",
        "gate_id": "GATE_A",
        "fail_count": 0
    }
    """
    data = request.get_json()
    uid = data.get("uid", "").strip()
    gate_id = data.get("gate_id", "UNKNOWN")
    fail_count = data.get("fail_count", 0)

    if not uid:
        return jsonify({"verified": False, "message": "UID가 없습니다"}), 400

    conn = get_db()
    cursor = conn.cursor()

    try:
        # ── 1단계: workers 테이블에서 UID로 작업자 찾기 ──
        cursor.execute(
            "SELECT id, name, company, role, is_active FROM workers WHERE nfc_uid = %s",
            (uid,)
        )
        worker = cursor.fetchone()

        now = datetime.now()

        if worker and worker["is_active"]:
            # ====== 인증 성공 ======
            # 출입 기록 저장
            cursor.execute(
                """INSERT INTO access_logs 
                   (worker_id, gate_id, status, created_at) 
                   VALUES (%s, %s, 'SUCCESS', %s)""",
                (worker["id"], gate_id, now)
            )
            conn.commit()

            return jsonify({
                "verified": True,
                "worker": {
                    "id": worker["id"],
                    "name": worker["name"],
                    "company": worker["company"],
                    "role": worker["role"],
                },
                "message": f"{worker['name']}님, 출입이 허가되었습니다."
            })

        else:
            # ====== 인증 실패 ======
            # 실패 기록 저장
            cursor.execute(
                """INSERT INTO access_logs 
                   (worker_id, gate_id, nfc_uid_raw, status, created_at) 
                   VALUES (%s, %s, %s, 'FAIL', %s)""",
                (
                    worker["id"] if worker else None,
                    gate_id,
                    uid,
                    now,
                )
            )
            conn.commit()

            # 3회 이상 실패 → 관리자 푸시 알림 발송
            if fail_count >= 2:  # ESP32에서 0부터 세므로, 2 = 3회째
                send_admin_push(
                    title="⚠️ 미등록 인원 출입 시도",
                    body=f"출입구 {gate_id}에서 미등록 NFC 카드(UID: {uid})가 "
                         f"3회 연속 인증 실패했습니다.",
                    data={
                        "type": "IDENTITY_FAIL",
                        "gate_id": gate_id,
                        "uid": uid,
                        "timestamp": now.isoformat(),
                    }
                )

            reason = "비활성 계정" if worker else "미등록 카드"
            return jsonify({
                "verified": False,
                "message": f"인증 실패: {reason}",
                "fail_count": fail_count + 1,
            })

    finally:
        cursor.close()
        conn.close()


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# API 2: 작업자 등록 (관리자 앱에서 호출)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
@app.route("/api/workers", methods=["POST"])
def register_worker():
    """
    관리자가 새 작업자를 등록할 때 사용
    {
        "name": "김철수",
        "company": "한빛건설",
        "role": "철근공",
        "phone": "010-1234-5678",
        "nfc_uid": "A3:B2:C1:D4"
    }
    """
    data = request.get_json()

    required = ["name", "nfc_uid"]
    for field in required:
        if not data.get(field):
            return jsonify({"error": f"{field} 필수입니다"}), 400

    conn = get_db()
    cursor = conn.cursor()

    try:
        # 중복 UID 확인
        cursor.execute(
            "SELECT id FROM workers WHERE nfc_uid = %s", (data["nfc_uid"],)
        )
        if cursor.fetchone():
            return jsonify({"error": "이미 등록된 NFC 카드입니다"}), 409

        cursor.execute(
            """INSERT INTO workers 
               (name, company, role, phone, nfc_uid, is_active, created_at) 
               VALUES (%s, %s, %s, %s, %s, TRUE, %s)""",
            (
                data["name"],
                data.get("company", ""),
                data.get("role", ""),
                data.get("phone", ""),
                data["nfc_uid"],
                datetime.now(),
            )
        )
        conn.commit()

        return jsonify({
            "message": f"{data['name']}님 등록 완료!",
            "worker_id": cursor.lastrowid,
        }), 201

    finally:
        cursor.close()
        conn.close()


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# API 3: 작업자 목록 조회 (관리자 앱에서 호출)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
@app.route("/api/workers", methods=["GET"])
def get_workers():
    conn = get_db()
    cursor = conn.cursor()
    try:
        cursor.execute(
            """SELECT id, name, company, role, phone, nfc_uid, is_active, created_at 
               FROM workers ORDER BY created_at DESC"""
        )
        workers = cursor.fetchall()

        # datetime을 문자열로 변환
        for w in workers:
            if w.get("created_at"):
                w["created_at"] = w["created_at"].isoformat()

        return jsonify({"workers": workers})
    finally:
        cursor.close()
        conn.close()


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# API 4: 오늘의 출입 기록 (대시보드용)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
@app.route("/api/access-logs/today", methods=["GET"])
def get_today_logs():
    conn = get_db()
    cursor = conn.cursor()
    try:
        today = datetime.now().strftime("%Y-%m-%d")
        cursor.execute(
            """SELECT al.id, al.gate_id, al.status, al.nfc_uid_raw, al.created_at,
                      w.name, w.company
               FROM access_logs al
               LEFT JOIN workers w ON al.worker_id = w.id
               WHERE DATE(al.created_at) = %s
               ORDER BY al.created_at DESC""",
            (today,)
        )
        logs = cursor.fetchall()

        for log in logs:
            if log.get("created_at"):
                log["created_at"] = log["created_at"].isoformat()

        # 오늘 통계
        cursor.execute(
            """SELECT 
                 COUNT(*) as total,
                 SUM(CASE WHEN status='SUCCESS' THEN 1 ELSE 0 END) as success_count,
                 SUM(CASE WHEN status='FAIL' THEN 1 ELSE 0 END) as fail_count
               FROM access_logs 
               WHERE DATE(created_at) = %s""",
            (today,)
        )
        stats = cursor.fetchone()

        return jsonify({"logs": logs, "stats": stats})
    finally:
        cursor.close()
        conn.close()


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 관리자 푸시 알림 발송
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
def send_admin_push(title, body, data=None):
    """
    Firebase Cloud Messaging(FCM)으로 관리자 앱에 푸시 알림 보내기
    
    [나중에 설정할 것]
    1. Firebase 프로젝트 생성 (https://console.firebase.google.com)
    2. 프로젝트 설정 → 서비스 계정 → 새 비공개 키 생성 → firebase-key.json 저장
    3. 위에 주석처리된 firebase_admin import 부분 활성화
    4. Flutter 앱에서 FCM 토큰 받아서 admin_devices 테이블에 저장
    """
    print(f"[푸시 알림] {title}: {body}")

    # ── 실제 FCM 발송 코드 (Firebase 설정 후 주석 해제) ──
    # conn = get_db()
    # cursor = conn.cursor()
    # cursor.execute("SELECT fcm_token FROM admin_devices WHERE is_active = TRUE")
    # devices = cursor.fetchall()
    # cursor.close()
    # conn.close()
    #
    # for device in devices:
    #     message = messaging.Message(
    #         notification=messaging.Notification(title=title, body=body),
    #         data={k: str(v) for k, v in (data or {}).items()},
    #         token=device["fcm_token"],
    #     )
    #     try:
    #         messaging.send(message)
    #     except Exception as e:
    #         print(f"푸시 발송 실패: {e}")
    pass


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 서버 실행
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
if __name__ == "__main__":
    print("=" * 50)
    print("  NFC 신원확인 서버 시작!")
    print("  http://0.0.0.0:5000")
    print("=" * 50)
    
    # host="0.0.0.0" → 같은 WiFi의 다른 기기(ESP32)에서 접근 가능
    app.run(host="0.0.0.0", port=5000, debug=True)
