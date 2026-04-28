import os
from flask import Flask, jsonify, request
from flask_cors import CORS
import sqlite3
from datetime import datetime
from werkzeug.utils import secure_filename
import firebase_admin
from firebase_admin import credentials, messaging

app = Flask(__name__)
CORS(app)

# 🚀 파이어베이스 관리자 초기화 (test_push.py에서 하던 역할 흡수)
cred = credentials.Certificate("firebase_key.json")
firebase_admin.initialize_app(cred)

UPLOAD_FOLDER = 'static/images'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

def get_db_connection():
    conn = sqlite3.connect('safety.db')
    conn.row_factory = sqlite3.Row
    return conn

# =====================================================================
# 1. 플러터 앱이 최신 토큰을 보내면 DB에 저장하는 통로
# =====================================================================
@app.route('/api/token', methods=['POST'])
def save_token():
    data = request.json
    token = data.get('token')
    
    if token:
        conn = get_db_connection()
        cursor = conn.cursor()
        # 이전 토큰은 지우고 최신 토큰 1개만 유지 (1인 관리자 기준)
        cursor.execute('DELETE FROM admin_tokens')
        cursor.execute('INSERT INTO admin_tokens (token) VALUES (?)', (token,))
        conn.commit()
        conn.close()
        print(f"✅ 새 토큰이 DB에 저장되었습니다.")
        return jsonify({"message": "토큰 저장 성공"}), 200
    return jsonify({"error": "토큰이 없습니다."}), 400

# =====================================================================
# 2. 대시보드 리스트 출력용
# =====================================================================
@app.route('/api/alerts', methods=['GET'])
def get_alerts():
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('''
        SELECT v.log_id, w.name AS worker_name, v.issue, v.time, v.status_color, v.image_url 
        FROM violation_logs v
        JOIN workers w ON v.worker_id = w.worker_id
        ORDER BY v.log_id DESC
    ''')
    rows = cursor.fetchall()
    conn.close()

    alerts = [{"id": str(r['log_id']), "workerName": r['worker_name'], "issue": r['issue'], "time": r['time'], "statusColor": r['status_color'], "imageUrl": r['image_url']} for r in rows]
    return jsonify(alerts)

# =====================================================================
# 3. 젯슨이 위반 데이터를 보낼 때 -> DB 저장 후 "자동으로 알림 발사!"
# =====================================================================
@app.route('/api/alerts', methods=['POST'])
def add_alert():
    # 1. 요청으로부터 데이터 받기
    worker_name = request.form.get('workerName', '미상')
    issue = request.form.get('issue', '위반 발생')
    status_color = request.form.get('statusColor', 'red')
    
    # 🚨 알림에 표시할 제목과 내용 정의
    title = "⚠️ 안전 위반 감지"
    body = f"{worker_name} 작업자: {issue}"
    
    now = datetime.now()
    now_time = now.strftime("%H:%M")
    image_url = f"{request.host_url}static/images/test.jpg"

    conn = get_db_connection()
    cursor = conn.cursor()

    # 3-1. 작업자 조회 및 로그 저장
    cursor.execute("SELECT worker_id FROM workers WHERE name = ?", (worker_name,))
    worker_row = cursor.fetchone()
    
    if worker_row:
        worker_id = worker_row['worker_id']
    else:
        cursor.execute("INSERT INTO workers (name, role) VALUES (?, ?)", (worker_name, '미등록'))
        worker_id = cursor.lastrowid

    cursor.execute('''
        INSERT INTO violation_logs (worker_id, issue, time, status_color, image_url)
        VALUES (?, ?, ?, ?, ?)
    ''', (worker_id, issue, now_time, status_color, image_url))
    
    # 방금 저장된 로그의 ID 가져오기 (알림 데이터용)
    log_id = cursor.lastrowid
    
    # 3-2. 관리자 토큰 조회
    cursor.execute("SELECT token FROM admin_tokens ORDER BY id DESC LIMIT 1")
    token_row = cursor.fetchone()
    conn.commit()
    conn.close()

    if token_row:
        target_token = token_row['token']
        # 🔔 알림 메시지 구성
        message = messaging.Message(
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            # 🚀 [추가됨] 앱에서 알림을 클릭했을 때 사진과 함께 상세 화면을 띄워주기 위한 숨겨진 데이터
            data={
                'id': str(log_id),
                'workerName': worker_name,
                'issue': issue,
                'time': now_time,
                'imageUrl': image_url
            },
            android=messaging.AndroidConfig(
                priority='high',
                notification=messaging.AndroidNotification(
                    channel_id='high_importance_channel',
                    priority='high'
                ),
            ),
            token=target_token,
        )
        try:
            messaging.send(message)
            print(f"✅ 알림 전송 성공! 대상: {worker_name}")
        except Exception as e:
            print(f"🚨 푸시 알림 전송 실패: {e}")

    return jsonify({"message": "성공"}), 201

# =====================================================================
# 4. 앱의 "작업자 관리" 탭에 데이터를 보내주는 통로 (🚀 새로 추가됨)
# =====================================================================
@app.route('/api/workers', methods=['GET'])
def get_workers():
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # 작업자별 위반 횟수와 가장 최근 위반 사유를 계산합니다.
    cursor.execute('''
        SELECT w.name, 
               COUNT(v.log_id) as violationCount,
               (SELECT issue FROM violation_logs WHERE worker_id = w.worker_id ORDER BY log_id DESC LIMIT 1) as lastViolation
        FROM workers w
        LEFT JOIN violation_logs v ON w.worker_id = v.worker_id
        GROUP BY w.worker_id
        ORDER BY violationCount DESC
    ''')
    rows = cursor.fetchall()
    conn.close()

    workers_list = []
    for row in rows:
        workers_list.append({
            "name": row["name"],
            "violationCount": row["violationCount"],
            "lastViolation": row["lastViolation"] if row["lastViolation"] else "기록 없음"
        })

    return jsonify(workers_list), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)