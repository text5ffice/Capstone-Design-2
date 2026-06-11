import os
import cv2
import numpy as np
import math
import time
import json
import threading
from collections import deque
from flask import Flask, jsonify, request, Response, render_template, send_from_directory
from flask_cors import CORS
import sqlite3
from datetime import datetime
import firebase_admin
from firebase_admin import credentials, messaging
from ultralytics import YOLO
from PIL import ImageFont, ImageDraw, Image

app = Flask(__name__)
CORS(app)

# =====================================================================
# 1. 초기화 및 듀얼 AI 모델 로드
# =====================================================================
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
AUDIO_FOLDER = os.path.join(BASE_DIR, 'audio') 
UPLOAD_FOLDER = os.path.join(BASE_DIR, 'static', 'images')
ZONE_FILE = "danger_zones.json"
PPE_SETTINGS_FILE = "ppe_settings.json"
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

try:
    cred = credentials.Certificate("firebase_key.json")
    firebase_admin.initialize_app(cred)
except Exception: pass

print("⏳ AI 모델 로드 중...")
pose_model = YOLO('yolov8m-pose.pt') 
ppe_model = YOLO('best.pt')          
print("✅ 듀얼 AI 모델 로드 완료!")

def get_db_connection():
    conn = sqlite3.connect('safety.db')
    conn.row_factory = sqlite3.Row
    return conn

def put_korean_text(img, text, position, font_size, color):
    img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    img_pil = Image.fromarray(img_rgb)
    draw = ImageDraw.Draw(img_pil)
    try: font = ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc", font_size)
    except:
        try: font = ImageFont.truetype("malgun.ttf", font_size)
        except: font = ImageFont.load_default()
    b, g, r = color
    draw.text(position, text, font=font, fill=(r, g, b))
    return cv2.cvtColor(np.array(img_pil), cv2.COLOR_RGB2BGR)

# =====================================================================
# 2. [출입 시스템] 선입선출(FIFO) 로직
# =====================================================================
latest_entry_frame = b'' 
system_active = False
system_status = "IDLE"  
pause_until = 0
current_worker_name = None
current_missing = []
status_history = deque(maxlen=5) 
pending_fifo_queue = deque() 
latest_scanned_uid = ""

CLASS_MAP = {'Hardhat': 'helmet', 'helmet': 'helmet', 'Safety_Vest': 'vest', 'vest': 'vest', 'Mask': 'mask', 'mask': 'mask', 'Gloves': 'gloves', 'gloves': 'gloves'}
KOR_MAP = {'helmet': '안전모', 'vest': '조끼', 'mask': '마스크', 'gloves': '장갑'}

def load_ppe_settings():
    default = {"helmet": True, "vest": True, "mask": False, "gloves": False}
    if os.path.exists(PPE_SETTINGS_FILE):
        with open(PPE_SETTINGS_FILE, "r", encoding="utf-8") as f:
            try: return json.load(f)
            except: return default
    return default
ACTIVE_PPE = load_ppe_settings()

@app.route('/')
def index(): return render_template('index.html')

@app.route('/audio/<filename>')
def serve_audio(filename): return send_from_directory(AUDIO_FOLDER, filename)

@app.route('/set_active', methods=['POST'])
def set_active():
    global system_active, status_history, pause_until, system_status, current_worker_name, current_missing
    data = request.json
    system_active = data.get('active', False)
    status_history.clear()
    pause_until = 0; system_status = "IDLE"; current_worker_name = None; current_missing = []
    return jsonify({'status': 'success'})

@app.route('/update_settings', methods=['POST'])
def update_settings():
    global ACTIVE_PPE
    data = request.json
    for key in ACTIVE_PPE.keys():
        if key in data: ACTIVE_PPE[key] = data[key]
    with open(PPE_SETTINGS_FILE, "w", encoding="utf-8") as f: json.dump(ACTIVE_PPE, f)
    return jsonify({'status': 'success'})

@app.route('/current_status')
def get_current_status():
    global system_status, pause_until, current_worker_name, current_missing
    web_status = system_status
    if system_status == "PASS": web_status = "OK"
    elif system_status == "FAIL": web_status = "WARNING"
    current_time = time.time()
    countdown = max(0, int(pause_until - current_time)) if pause_until > current_time else 0
    return jsonify({'status': web_status, 'worker': current_worker_name, 'countdown': countdown, 'missing': current_missing})

@app.route('/api/entry_check', methods=['POST'])
def entry_check():
    global pause_until, system_status, current_worker_name, current_missing, status_history
    global pending_fifo_queue, latest_entry_frame, latest_scanned_uid
    
    if 'image' not in request.files: return jsonify({'status': 'ERROR'})
    file = request.files['image']
    uid = request.form.get('uid', '').strip() 
    if uid: latest_scanned_uid = uid

    nparr = np.frombuffer(file.read(), np.uint8)
    frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    ret, buffer = cv2.imencode('.jpg', frame)
    if ret: latest_entry_frame = buffer.tobytes()

    if not system_active: return jsonify({'status': 'IDLE'})
    current_time = time.time()

    if current_time < pause_until:
        return jsonify({'status': system_status, 'worker': current_worker_name, 'missing': current_missing})

    if system_status == "WAIT_SCANNING":
        system_status = "SCANNING"; status_history.clear()
    elif system_status == "FAIL":
        system_status = "SCANNING"; status_history.clear(); current_missing = []
    elif system_status in ["PASS", "REJECT"]:
        system_status = "IDLE"; current_worker_name = None; current_missing = []; status_history.clear()

    if uid and system_status == "IDLE":
        conn = get_db_connection()
        worker = conn.execute("SELECT name FROM workers WHERE uid = ?", (uid,)).fetchone()
        conn.close()
        if not worker:
            system_status = "REJECT"; pause_until = current_time + 3.0
        else:
            current_worker_name = worker['name']; system_status = "WAIT_SCANNING"; pause_until = current_time + 3.0
        return jsonify({'status': system_status, 'worker': current_worker_name, 'missing': current_missing})

    if system_status == "SCANNING" and current_worker_name:
        results = ppe_model(frame, conf=0.6, verbose=False)
        detected = []
        if results and len(results) > 0:
            for box in results[0].boxes: detected.append(CLASS_MAP.get(ppe_model.names[int(box.cls[0])], ''))
        current_missing = [t for t, req in ACTIVE_PPE.items() if req and t not in detected]
        status_history.append("FAIL" if current_missing else "PASS")
        
        if len(status_history) == 5:
            if status_history.count("PASS") >= 3:
                system_status = "PASS"; pause_until = current_time + 5.0
                pending_fifo_queue.append((current_worker_name, current_time)) 
            elif status_history.count("FAIL") >= 3:
                system_status = "FAIL"; pause_until = current_time + 6.0 
        return jsonify({'status': system_status, 'worker': current_worker_name, 'missing': current_missing})
    return jsonify({'status': 'IDLE'})

def generate_entry_frames():
    global latest_entry_frame
    while True:
        if latest_entry_frame: yield (b'--frame\r\nContent-Type: image/jpeg\r\n\r\n' + latest_entry_frame + b'\r\n')
        time.sleep(0.05)

@app.route('/video_feed')  
def video_feed(): return Response(generate_entry_frames(), mimetype='multipart/x-mixed-replace; boundary=frame')

# =====================================================================
# 3. [관제 시스템 - 카메라 2] 쓰러짐/무동작/PPE 10초 연속 감지
# =====================================================================
latest_monitor_frame = b'' 
prev_heights = {}
track_movement_state = {} 
active_trackers = {} 
last_zone_alert = {} 

# 🚀 아이디 복사 방지용 '분실물 보관소' 딕셔너리
lost_id_recovery = {} 

def load_zones():
    if os.path.exists(ZONE_FILE):
        with open(ZONE_FILE, "r", encoding="utf-8") as f:
            try:
                zones = json.load(f)
                for z in zones:
                    z["inner_polygon"] = [tuple(p) for p in z.get("inner_polygon", [])]
                    z["outer_polygon"] = [tuple(p) for p in z.get("outer_polygon", [])]
                return zones
            except: return []
    return []
DANGER_ZONES = load_zones()

def is_fallen(keypoints, bbox, prev_height=None, confidence_threshold=0.5):
    kp = keypoints
    l_shoulder = kp[5] if kp[5][2] > confidence_threshold else None
    r_shoulder = kp[6] if kp[6][2] > confidence_threshold else None
    l_hip = kp[11] if kp[11][2] > confidence_threshold else None
    r_hip = kp[12] if kp[12][2] > confidence_threshold else None
    fall_score = 0
    x1, y1, x2, y2 = bbox
    width = x2 - x1; height = y2 - y1
    if height > 0:
        aspect_ratio = width / height
        if aspect_ratio > 1.2: fall_score += 40
        elif aspect_ratio > 0.9: fall_score += 15
    if l_shoulder is not None and r_shoulder is not None and l_hip is not None and r_hip is not None:
        dx = ((l_hip[0] + r_hip[0])/2) - ((l_shoulder[0] + r_shoulder[0])/2)
        dy = ((l_hip[1] + r_hip[1])/2) - ((l_shoulder[1] + r_shoulder[1])/2)
        if abs(math.degrees(math.atan2(dx, dy))) > 50: fall_score += 40
    if prev_height is not None and prev_height > 0 and height > 0:
        if (height / prev_height) < 0.6: fall_score += 35
    return fall_score >= 60

def point_in_polygon(point, polygon):
    if not polygon or len(polygon) < 3: return False
    x, y = point; inside = False; px, py = polygon[-1]
    for qx, qy in polygon:
        if ((py > y) != (qy > y)) and (x < (qx - px) * (y - py) / (qy - py) + px): inside = not inside
        px, py = qx, qy
    return inside

def trigger_alert(worker_name, issue, status_color, filename):
    if worker_name == "미확인":
        return

    now_date = datetime.now().strftime("%Y-%m-%d") 
    now_time = datetime.now().strftime("%H:%M")
    image_url = f"http://192.168.0.8:1557/static/images/{filename}" 

    conn = get_db_connection(); cursor = conn.cursor()
    worker_row = cursor.execute("SELECT worker_id FROM workers WHERE name = ?", (worker_name,)).fetchone()
    if worker_row: worker_id = worker_row['worker_id']
    else:
        cursor.execute("INSERT INTO workers (name, role) VALUES (?, ?)", (worker_name, '미등록'))
        worker_id = cursor.lastrowid
    cursor.execute('INSERT INTO violation_logs (worker_id, issue, date, time, status_color, image_url, is_checked) VALUES (?, ?, ?, ?, ?, ?, 0)', (worker_id, issue, now_date, now_time, status_color, image_url))
    log_id = cursor.lastrowid
    
    token_row = cursor.execute("SELECT token FROM admin_tokens ORDER BY id DESC LIMIT 1").fetchone()
    conn.commit(); conn.close()

    if token_row:
        try:
            message = messaging.Message(
                data={'id': str(log_id), 'workerName': worker_name, 'issue': issue, 'date': now_date, 'time': now_time, 'imageUrl': image_url, 'title': '⚠️ 위반 알림', 'body': f"{worker_name}: {issue}"},
                android=messaging.AndroidConfig(priority='high'), token=token_row['token'],
            )
            messaging.send(message)
            print(f"✅ 푸시 알림 전송 성공: {worker_name} ({issue})")
        except Exception as e: 
            print(f"❌ 파이어베이스 푸시 에러: {e}")

@app.route('/api/analyze_frame', methods=['POST'])
def analyze_frame():
    global prev_heights, latest_monitor_frame, track_movement_state, last_zone_alert, DANGER_ZONES
    global pending_fifo_queue, active_trackers, lost_id_recovery
    
    file = request.files['image']
    npimg = np.frombuffer(file.read(), np.uint8)
    frame = cv2.imdecode(npimg, cv2.IMREAD_COLOR)
    frame = cv2.resize(frame, (1280, 720))
    current_time = time.time()
    
    # 큐 오래된 사람 날리기
    while pending_fifo_queue and current_time - pending_fifo_queue[0][1] > 30.0: pending_fifo_queue.popleft()

    for zone in DANGER_ZONES:
        inner_pts = zone.get('inner_polygon', [])
        if inner_pts:
            pts_array = np.array(inner_pts, np.int32)
            cv2.polylines(frame, [pts_array], True, (0, 0, 255), 2, cv2.LINE_AA)
            frame = put_korean_text(frame, zone['name'], tuple(inner_pts[0]), 20, (0, 0, 255))

    ppe_results = ppe_model(frame, conf=0.5, verbose=False)
    ppe_detected_boxes = []
    if ppe_results and len(ppe_results) > 0:
        for pbox in ppe_results[0].boxes:
            cls_name = CLASS_MAP.get(ppe_model.names[int(pbox.cls[0])], '')
            px1, py1, px2, py2 = map(int, pbox.xyxy[0])
            ppe_detected_boxes.append({'cls': cls_name, 'box': (px1, py1, px2, py2)})
            kor_name = KOR_MAP.get(cls_name, cls_name)
            if kor_name:
                cv2.rectangle(frame, (px1, py1), (px2, py2), (0, 255, 0), 2)
                frame = put_korean_text(frame, kor_name, (px1, max(0, py1 - 20)), 16, (0, 255, 0))

    pose_results = pose_model.track(frame, persist=True, verbose=False, conf=0.3)
    current_track_ids = []
    if pose_results and len(pose_results) > 0 and pose_results[0].boxes and pose_results[0].boxes.id is not None:
        current_track_ids = [int(box_id.item()) for box_id in pose_results[0].boxes.id]

    # 🚀 1. 1:1 매칭 및 복사 버그 방지 로직 적용 🚀
    # (1) 화면에서 사라진 ID 정리 및 분실물 보관소에 이름 등록
    disappeared_tids = set(active_trackers.keys()) - set(current_track_ids)
    for dtid in disappeared_tids:
        name = active_trackers.pop(dtid, "미확인")
        if name != "미확인":
            lost_id_recovery[name] = current_time # 5초간 기억해줌
        if dtid in track_movement_state: del track_movement_state[dtid]
        if dtid in prev_heights: del prev_heights[dtid]

    # (2) 새로 나타난 사람은 미확인 부여 (대기 중인 사람이 있으면 1명에게만 이름 할당)
    for tid in current_track_ids:
        if tid not in active_trackers:
            active_trackers[tid] = "미확인"
        
        # 만약 미확인 상태인데 문을 통과한 사람이 큐에 대기 중이라면?
        if active_trackers[tid] == "미확인" and pending_fifo_queue:
            assigned_name, _ = pending_fifo_queue.popleft()
            active_trackers[tid] = assigned_name # 이 사람한테만 부여 (큐 1명 소모)

    # (3) 그래도 아직 미확인인 사람이 있다면? 분실물 보관소 확인 (깜빡임 복구용)
    for tid in current_track_ids:
        if active_trackers[tid] == "미확인":
            for lost_name, lost_time in list(lost_id_recovery.items()):
                if current_time - lost_time < 5.0: # 사라진지 5초 이내라면
                    active_trackers[tid] = lost_name
                    del lost_id_recovery[lost_name] # 이름을 줬으니 보관소에서 뺌 (절대 2명에게 복사 안됨)
                    break
            
    for result in pose_results:
        if result.keypoints is None or result.boxes is None or result.boxes.id is None: continue
        for kp, box, track_id_tensor in zip(result.keypoints.data.cpu().numpy(), result.boxes.xyxy.cpu().numpy(), result.boxes.id):
            track_id = int(track_id_tensor.item())
            worker_name = active_trackers.get(track_id, "미확인")

            x1, y1, x2, y2 = map(int, box)
            cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
            
            if track_id not in track_movement_state: 
                track_movement_state[track_id] = {
                    'cx': cx, 'cy': cy, 'last_fall_alert': 0, 'last_ppe_alert': 0, 
                    'is_fallen': False, 'fall_start_time': 0, 'last_nomove_alert': 0
                }
            state = track_movement_state[track_id]
            frame = put_korean_text(frame, worker_name, (x1, max(0, y1 - 30)), 24, (255, 255, 0))

            is_falling_now = is_fallen(kp, box, prev_heights.get(track_id))
            
            if is_falling_now:
                if not state['is_fallen']:
                    state['is_fallen'] = True
                    state['fall_start_time'] = current_time
                    state['cx'] = cx
                    state['cy'] = cy
                    filename = f"fall_{track_id}_{int(current_time)}.jpg"
                    cv2.imwrite(os.path.join(UPLOAD_FOLDER, filename), frame)
                    trigger_alert(worker_name, '⚠️ 쓰러짐 감지!', 'orange', filename)
                else:
                    dist = math.hypot(cx - state['cx'], cy - state['cy'])
                    if dist < 30:
                        if current_time - state['fall_start_time'] >= 10.0:
                            if current_time - state['last_nomove_alert'] >= 10.0:
                                state['last_nomove_alert'] = current_time
                                filename = f"nomove_{track_id}_{int(current_time)}.jpg"
                                cv2.imwrite(os.path.join(UPLOAD_FOLDER, filename), frame)
                                trigger_alert(worker_name, '🚨 쓰러짐 후 10초 의식/움직임 없음!', 'red', filename)
                    else:
                        state['cx'] = cx
                        state['cy'] = cy
                        state['fall_start_time'] = current_time 
                
                frame = put_korean_text(frame, "🚨 쓰러짐 감지", (x1, max(0, y1 - 60)), 24, (0, 165, 255))
            else:
                state['is_fallen'] = False
                state['cx'] = cx
                state['cy'] = cy
                cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)

            if not state['is_fallen']:
                # 1️⃣ PPE 무단 탈의 검사
                person_ppe = set()
                for ppe in ppe_detected_boxes:
                    px1, py1, px2, py2 = ppe['box']
                    pcx, pcy = (px1 + px2) / 2, (py1 + py2) / 2
                    if x1 <= pcx <= x2 and y1 <= pcy <= y2: person_ppe.add(ppe['cls'])
                        
                missing_ppe = [t for t, req in ACTIVE_PPE.items() if req and t not in person_ppe]
                if missing_ppe:
                    if current_time - state.get('last_ppe_alert', 0) > 10:
                        state['last_ppe_alert'] = current_time
                        kor_missing = [KOR_MAP.get(m, m) for m in missing_ppe]
                        filename = f"ppe_{track_id}_{int(current_time)}.jpg"
                        cv2.imwrite(os.path.join(UPLOAD_FOLDER, filename), frame)
                        trigger_alert(worker_name, f'⚠️ 현장 내부 미착용 ({", ".join(kor_missing)})', 'orange', filename)
                    frame = put_korean_text(frame, "장비 미착용!", (x1, y2 + 10), 20, (0, 0, 255))

                # 2️⃣ 구역 진입 검사
                is_inside = False; zone_name_str = ""
                for zone in DANGER_ZONES:
                    if point_in_polygon((cx, y2), zone.get("inner_polygon", [])):
                        is_inside = True; zone_name_str = zone['name']; break
                if is_inside:
                    if current_time - last_zone_alert.get(track_id, 0) > 10:
                        last_zone_alert[track_id] = current_time
                        cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 0, 255), 4)
                        filename = f"zone_{track_id}_{int(current_time)}.jpg"
                        cv2.imwrite(os.path.join(UPLOAD_FOLDER, filename), frame)
                        trigger_alert(worker_name, f'🚨 [{zone_name_str}] 무단 진입!', 'red', filename)

            prev_heights[track_id] = y2 - y1

    ret, buffer = cv2.imencode('.jpg', frame)
    if ret: latest_monitor_frame = buffer.tobytes()
    return jsonify({"message": "분석 성공"}), 200

def generate_monitor_frames():
    global latest_monitor_frame
    while True:
        if latest_monitor_frame: yield (b'--frame\r\nContent-Type: image/jpeg\r\n\r\n' + latest_monitor_frame + b'\r\n')
        time.sleep(0.05)

@app.route('/api/video_feed') 
def api_video_feed(): return Response(generate_monitor_frames(), mimetype='multipart/x-mixed-replace; boundary=frame')

# =====================================================================
# 4. 플러터 연동 API
# =====================================================================

@app.route('/api/token', methods=['POST', 'DELETE'])
def handle_token():
    conn = get_db_connection()
    if request.method == 'POST':
        token = request.json.get('token')
        if token:
            conn.execute('DELETE FROM admin_tokens')
            conn.execute('INSERT INTO admin_tokens (token) VALUES (?)', (token,))
            conn.commit(); conn.close()
            print(f"\n==========================================")
            print(f"📲 기기 푸시 알림 토큰 갱신 완료!")
            print(f"==========================================\n")
            return jsonify({"message": "Token saved"}), 200
        return jsonify({"message": "No token"}), 400
    elif request.method == 'DELETE':
        conn.execute('DELETE FROM admin_tokens')
        conn.commit(); conn.close()
        return jsonify({"message": "Token deleted"}), 200

@app.route('/api/latest_uid', methods=['GET', 'DELETE'])
def handle_latest_uid():
    global latest_scanned_uid
    if request.method == 'GET': return jsonify({"uid": latest_scanned_uid}), 200
    elif request.method == 'DELETE': latest_scanned_uid = ""; return jsonify({"message": "cleared"}), 200

@app.route('/api/login', methods=['POST'])
def login(): 
    user_id = request.json.get('id', '')
    if user_id == 'admin': return jsonify({"role": "안전관리자", "message": "로그인 성공"}), 200
    elif user_id == 'manager': return jsonify({"role": "현장소장", "message": "로그인 성공"}), 200
    else: return jsonify({"message": "로그인 권한 없음"}), 401

@app.route('/api/settings/ppe', methods=['GET', 'POST'])
def handle_ppe():
    global ACTIVE_PPE
    if request.method == 'POST':
        ACTIVE_PPE = request.json
        with open(PPE_SETTINGS_FILE, "w", encoding="utf-8") as f: json.dump(ACTIVE_PPE, f)
        return jsonify({"message": "업데이트 완료"}), 200
    return jsonify(ACTIVE_PPE), 200

@app.route('/api/zones', methods=['GET', 'POST'])
def handle_zones():
    global DANGER_ZONES
    if request.method == 'POST':
        DANGER_ZONES = request.json
        with open(ZONE_FILE, "w", encoding="utf-8") as f: json.dump(DANGER_ZONES, f)
        return jsonify({"message": "저장 성공"}), 200
    return jsonify(DANGER_ZONES), 200

@app.route('/api/alerts', methods=['GET'])
def get_alerts():
    conn = get_db_connection()
    rows = conn.execute('SELECT v.log_id, w.name AS worker_name, v.issue, v.date, v.time, v.status_color, v.image_url, v.is_checked FROM violation_logs v JOIN workers w ON v.worker_id = w.worker_id ORDER BY v.log_id DESC').fetchall()
    conn.close()
    return jsonify([{"id": str(r['log_id']), "workerName": r['worker_name'], "issue": r['issue'], "date": r['date'], "time": r['time'], "statusColor": r['status_color'], "imageUrl": r['image_url'], "isChecked": r['is_checked']} for r in rows])

@app.route('/api/alerts/<int:log_id>/check', methods=['PUT'])
def check_alert(log_id):
    conn = get_db_connection()
    conn.execute('UPDATE violation_logs SET is_checked = 1 WHERE log_id = ?', (log_id,))
    conn.commit(); conn.close()
    return jsonify({"message": "확인 완료"}), 200

@app.route('/api/alerts/<int:log_id>', methods=['DELETE'])
def delete_alert(log_id):
    conn = get_db_connection()
    conn.execute('DELETE FROM violation_logs WHERE log_id = ?', (log_id,))
    conn.commit(); conn.close()
    return jsonify({"message": "삭제 완료"}), 200

@app.route('/api/workers', methods=['GET', 'POST'])
def manage_workers():
    conn = get_db_connection()
    if request.method == 'POST':
        data = request.json
        uid = data.get('uid', '').strip(); name = data.get('name', '신규작업자'); role = data.get('role', '작업자')
        conn.execute("INSERT INTO workers (name, role, uid) VALUES (?, ?, ?)", (name, role, uid))
        conn.commit(); conn.close()
        return jsonify({"message": "등록 완료"}), 200
    rows = conn.execute('SELECT w.worker_id, w.name, w.uid, COUNT(v.log_id) as violationCount, (SELECT issue FROM violation_logs WHERE worker_id = w.worker_id ORDER BY log_id DESC LIMIT 1) as lastViolation FROM workers w LEFT JOIN violation_logs v ON w.worker_id = v.worker_id GROUP BY w.worker_id ORDER BY violationCount DESC').fetchall()
    conn.close()
    return jsonify([{"id": r["worker_id"], "name": r["name"], "uid": r["uid"] if r["uid"] else "미등록", "violationCount": r["violationCount"], "lastViolation": r["lastViolation"] if r["lastViolation"] else "기록 없음"} for r in rows])

@app.route('/api/workers/<int:worker_id>/logs', methods=['GET'])
def get_worker_logs(worker_id):
    conn = get_db_connection()
    rows = conn.execute('SELECT log_id, issue, date, time, status_color, image_url, is_checked FROM violation_logs WHERE worker_id = ? ORDER BY log_id DESC', (worker_id,)).fetchall()
    conn.close()
    return jsonify([{"id": r['log_id'], "issue": r['issue'], "date": r['date'], "time": r['time'], "statusColor": r['status_color'], "imageUrl": r['image_url'], "isChecked": r['is_checked']} for r in rows])

@app.route('/api/workers/<int:worker_id>/logs/all', methods=['DELETE'])
def delete_all_worker_logs(worker_id):
    conn = get_db_connection()
    conn.execute('DELETE FROM violation_logs WHERE worker_id = ?', (worker_id,))
    conn.commit(); conn.close()
    return jsonify({"message": "전체 기록 삭제 완료"}), 200

@app.route('/api/workers/<int:worker_id>', methods=['DELETE'])
def delete_worker(worker_id):
    conn = get_db_connection()
    conn.execute('DELETE FROM violation_logs WHERE worker_id = ?', (worker_id,))
    conn.execute('DELETE FROM workers WHERE worker_id = ?', (worker_id,))
    conn.commit(); conn.close()
    return jsonify({"message": "삭제 완료"}), 200

def init_db():
    conn = sqlite3.connect('safety.db')
    conn.execute('''CREATE TABLE IF NOT EXISTS workers (worker_id INTEGER PRIMARY KEY, name TEXT, role TEXT)''')
    try: conn.execute("SELECT uid FROM workers LIMIT 1")
    except sqlite3.OperationalError: conn.execute("ALTER TABLE workers ADD COLUMN uid TEXT")
    conn.execute('''CREATE TABLE IF NOT EXISTS violation_logs (log_id INTEGER PRIMARY KEY, worker_id INTEGER, issue TEXT, date TEXT, time TEXT, status_color TEXT, image_url TEXT, is_checked INTEGER DEFAULT 0)''')
    conn.execute('''CREATE TABLE IF NOT EXISTS admin_tokens (id INTEGER PRIMARY KEY, token TEXT)''')
    conn.commit(); conn.close()

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=1557, debug=False, threaded=True)