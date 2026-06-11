"""
main.py — 전체 파이프라인 통합 실행

실행 모드:
    python main.py                # 더미 시나리오 (카메라 없이 테스트)
    python main.py --mode mouse   # 마우스로 수동 테스트
    python main.py --mode calib   # 최초 1회: 카메라 캘리브레이션
    python main.py --mode setzone # 위험구역 폴리곤 설정
    python main.py --mode live    # 실제 카메라 연결

전체 흐름:
    카메라 (비스듬 설치)
        ↓
    YOLO → bbox, foot_pixel (픽셀 좌표)
        ↓
    Homography → 바닥 좌표 (cm) 변환  ← 원근 왜곡 제거
        ↓
    zone_detector → outer/inner 면 기준 판별 (cm 단위)
        ↓
    반응 처리 + 시각화
"""

import cv2
import numpy as np
import argparse
import time

from zone_detector import check_all_zones, DANGER_ZONES
from yolo_dummy import get_detections
from homography import (
    load_homography, pixel_to_floor,
    calibrate_from_camera, set_zones_interactive, load_zones
)

# ────────────────────────────────────────
# 설정
# ────────────────────────────────────────

FRAME_W, FRAME_H = 720, 540
FONT = cv2.FONT_HERSHEY_SIMPLEX

COLOR = {
    "outside":  (80,  200, 80),
    "boundary": (0,   165, 255),
    "inside":   (40,  40,  220),
}
LABEL_KOR = {
    "outside":  "안전",
    "boundary": "경계 진입",
    "inside":   "구역 진입!",
}


# ────────────────────────────────────────
# 그리기
# ────────────────────────────────────────

def draw_zones(frame, zones, worker_statuses):
    priority = {"inside": 2, "boundary": 1, "outside": 0}

    for zone in zones:
        zone_status = "outside"
        for ws in worker_statuses.values():
            for r in ws["results"]:
                if r["zone_id"] == zone["id"]:
                    if priority[r["status"]] > priority[zone_status]:
                        zone_status = r["status"]

        outer_pts = np.array(zone["outer_polygon"], dtype=np.int32)
        inner_pts = np.array(zone["inner_polygon"], dtype=np.int32)

        # outer 면
        overlay = frame.copy()
        oc = COLOR["boundary"] if zone_status in ("boundary","inside") else (100,80,30)
        oa = 0.20 if zone_status == "boundary" else (0.15 if zone_status == "inside" else 0.07)
        cv2.fillPoly(overlay, [outer_pts], oc)
        cv2.addWeighted(overlay, oa, frame, 1-oa, 0, frame)
        cv2.polylines(frame, [outer_pts], True, oc, 1, cv2.LINE_AA)

        # inner 면
        overlay = frame.copy()
        ic = COLOR["inside"] if zone_status == "inside" else (180,40,40)
        ia = 0.32 if zone_status == "inside" else 0.12
        cv2.fillPoly(overlay, [inner_pts], ic)
        cv2.addWeighted(overlay, ia, frame, 1-ia, 0, frame)
        cv2.polylines(frame, [inner_pts], True, ic,
                      2 if zone_status == "inside" else 1, cv2.LINE_AA)

        cx = int(np.mean([p[0] for p in zone["inner_polygon"]]))
        cy = int(np.mean([p[1] for p in zone["inner_polygon"]]))
        cv2.putText(frame, zone["name"], (cx-60, cy-6),
                    FONT, 0.42, (255,255,255), 1, cv2.LINE_AA)
        cv2.putText(frame, "[위험]", (cx-20, cy+12),
                    FONT, 0.35, (200,120,120), 1, cv2.LINE_AA)


def draw_worker(frame, detection, floor_pt, status):
    x1, y1, x2, y2 = detection["bbox"]
    color = COLOR[status]

    cv2.rectangle(frame, (x1,y1), (x2,y2), color, 2)

    label = f"{detection['worker_id']} {detection['confidence']:.0%}"
    (lw,lh),_ = cv2.getTextSize(label, FONT, 0.45, 1)
    cv2.rectangle(frame, (x1, y1-lh-8), (x1+lw+6, y1), color, -1)
    cv2.putText(frame, label, (x1+3, y1-4), FONT, 0.45, (255,255,255), 1)

    fx, fy = int(detection["foot_pixel"][0]), int(detection["foot_pixel"][1])
    cv2.circle(frame, (fx,fy), 5, (255,255,0), -1, cv2.LINE_AA)
    cv2.circle(frame, (fx,fy), 9, (255,255,0), 1,  cv2.LINE_AA)

    if floor_pt:
        cv2.putText(frame, f"({floor_pt[0]:.0f},{floor_pt[1]:.0f})cm",
                    (fx-35, fy+18), FONT, 0.32, (200,200,100), 1)

    cv2.putText(frame, LABEL_KOR[status], (x1, y2+18),
                FONT, 0.52, color, 2, cv2.LINE_AA)


def draw_info(frame, frame_idx, n_workers, has_homo):
    homo_txt = "Homography ON" if has_homo else "Homography OFF (픽셀직접)"
    homo_color = (100,220,100) if has_homo else (80,80,220)
    steps = [
        f"1. YOLO  → {n_workers}명 감지",
        f"2. foot  → bbox 하단 중심",
        f"3. {homo_txt}",
        f"4. Poly  → outer/inner 면 판별",
    ]
    for i,s in enumerate(steps):
        c = homo_color if i == 2 else (180,220,255)
        cv2.putText(frame, s, (10, 22+i*19), FONT, 0.37, c, 1)
    cv2.putText(frame, f"frame:{frame_idx}  SPACE:일시정지  ESC:종료",
                (10, FRAME_H-10), FONT, 0.36, (100,100,100), 1)


def draw_status_panel(frame, worker_statuses):
    panel_x = FRAME_W - 200
    h = 35 + len(worker_statuses) * 50
    cv2.rectangle(frame, (panel_x,8), (FRAME_W-8, 8+h), (25,25,25), -1)
    cv2.rectangle(frame, (panel_x,8), (FRAME_W-8, 8+h), (70,70,70), 1)
    cv2.putText(frame, "작업자 상태", (panel_x+10,28), FONT, 0.44, (200,200,200), 1)

    for i, (wid, result) in enumerate(worker_statuses.items()):
        y = 50 + i*50
        status = result["most_critical"]
        color = COLOR[status]
        zone = result["critical_zone"] or "안전구역"
        cv2.putText(frame, wid, (panel_x+10,y), FONT, 0.4, (210,210,210), 1)
        cv2.rectangle(frame, (panel_x+8, y+6), (FRAME_W-12, y+24), color, -1)
        cv2.putText(frame, LABEL_KOR[status], (panel_x+14, y+20),
                    FONT, 0.46, (255,255,255), 1)
        cv2.putText(frame, zone[:20], (panel_x+10, y+38),
                    FONT, 0.33, (150,150,150), 1)


# ────────────────────────────────────────
# 반응 처리
# ────────────────────────────────────────

_last_alert = {}

def handle_alerts(worker_statuses):
    now = time.time()
    for wid, result in worker_statuses.items():
        status = result["most_critical"]
        zone = result["critical_zone"]
        last = _last_alert.get(wid, {"status":"outside","time":0})
        if status != "outside" and (status != last["status"] or now-last["time"] > 3):
            if status == "boundary":
                print(f"[경계] {wid} → {zone} | 음성 + 적색 부저")
            elif status == "inside":
                print(f"[진입!!] {wid} → {zone} | 부저 + 관리자 푸시 알림")
            _last_alert[wid] = {"status":status,"time":now}


# ────────────────────────────────────────
# 메인 루프 공통
# ────────────────────────────────────────

def process_frame(frame, zones, H, frame_idx):
    """한 프레임 처리: YOLO → Homography → 판별 → 그리기"""
    detections = get_detections(frame_idx)
    worker_statuses = {}

    for det in detections:
        foot_pixel = det["foot_pixel"]

        # Homography가 있으면 바닥 좌표로 변환, 없으면 픽셀 그대로
        if H is not None:
            floor_pt = pixel_to_floor(foot_pixel, H)
        else:
            floor_pt = foot_pixel

        result = check_all_zones(floor_pt, zones)
        worker_statuses[det["worker_id"]] = result
        draw_worker(frame, det, floor_pt if H is not None else None, result["most_critical"])

    draw_zones(frame, zones, worker_statuses)
    draw_info(frame, frame_idx, len(detections), H is not None)
    draw_status_panel(frame, worker_statuses)
    handle_alerts(worker_statuses)


# ────────────────────────────────────────
# 실행 모드
# ────────────────────────────────────────

def run_demo(zones, H):
    """더미 시나리오 자동 재생 (카메라 없이)"""
    cv2.namedWindow("위험구역 판별 시스템")
    frame_idx, paused = 0, False
    print("\n[DEMO] ESC: 종료 / SPACE: 일시정지")

    while True:
        frame = np.zeros((FRAME_H, FRAME_W, 3), dtype=np.uint8)
        frame[:] = (20, 22, 30)
        process_frame(frame, zones, H, frame_idx)
        cv2.imshow("위험구역 판별 시스템", frame)

        key = cv2.waitKey(30) & 0xFF
        if key == 27: break
        if key == 32: paused = not paused
        if not paused: frame_idx = (frame_idx + 1) % 421

    cv2.destroyAllWindows()


def run_mouse(zones, H):
    """마우스로 발 위치 수동 테스트"""
    mouse = [360, 270]
    def on_mouse(event, x, y, flags, param):
        if event == cv2.EVENT_MOUSEMOVE:
            mouse[0], mouse[1] = x, y

    cv2.namedWindow("위험구역 판별 - 마우스 테스트")
    cv2.setMouseCallback("위험구역 판별 - 마우스 테스트", on_mouse)
    print("\n[MOUSE] 마우스로 발 위치 테스트. ESC: 종료")

    while True:
        frame = np.zeros((FRAME_H, FRAME_W, 3), dtype=np.uint8)
        frame[:] = (20, 22, 30)

        px, py = mouse
        foot_pixel = (float(px), float(py))
        floor_pt = pixel_to_floor(foot_pixel, H) if H else foot_pixel
        result = check_all_zones(floor_pt, zones)
        status = result["most_critical"]

        det = {
            "worker_id": "worker_01",
            "bbox": (px-30, py-120, px+30, py),
            "confidence": 0.95,
            "foot_pixel": foot_pixel,
        }
        worker_statuses = {"worker_01": result}

        draw_zones(frame, zones, worker_statuses)
        draw_worker(frame, det, floor_pt if H else None, status)
        draw_info(frame, 0, 1, H is not None)
        draw_status_panel(frame, worker_statuses)

        cv2.imshow("위험구역 판별 - 마우스 테스트", frame)
        if cv2.waitKey(16) & 0xFF == 27: break

    cv2.destroyAllWindows()


def run_live(zones, H):
    """실제 카메라 연결 (YOLO 연결 후 사용)"""
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("카메라 연결 실패")
        return

    cv2.namedWindow("위험구역 판별 시스템 [LIVE]")
    frame_idx = 0
    print("\n[LIVE] 실제 카메라 연결. ESC: 종료")

    while True:
        ret, frame = cap.read()
        if not ret:
            break
        frame = cv2.resize(frame, (FRAME_W, FRAME_H))
        process_frame(frame, zones, H, frame_idx)
        cv2.imshow("위험구역 판별 시스템 [LIVE]", frame)
        frame_idx += 1

        if cv2.waitKey(1) & 0xFF == 27: break

    cap.release()
    cv2.destroyAllWindows()


# ────────────────────────────────────────
# 진입점
# ────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode",
        choices=["demo", "mouse", "calib", "setzone", "live"],
        default="demo")
    args = parser.parse_args()

    # ── 캘리브레이션 모드
    if args.mode == "calib":
        cap = cv2.VideoCapture(0)
        if not cap.isOpened():
            print("카메라 연결 실패")
        else:
            H = calibrate_from_camera(cap)
            cap.release()
        exit()

    # ── 위험구역 설정 모드
    if args.mode == "setzone":
        H = load_homography()
        if H is None:
            print("먼저 캘리브레이션을 실행하세요: python main.py --mode calib")
            exit()
        cap = cv2.VideoCapture(0)
        if not cap.isOpened():
            print("카메라 연결 실패")
        else:
            set_zones_interactive(cap, H)
            cap.release()
        exit()

    # ── 일반 실행 모드: Homography + Zone 로드
    H = load_homography()
    if H is None:
        print("[경고] 캘리브레이션 없음 → 픽셀 좌표 직접 사용")
        print("       정확한 판별을 위해: python main.py --mode calib\n")

    zones = load_zones()
    if zones is None:
        print("[경고] 저장된 구역 없음 → 기본 구역 사용")
        zones = DANGER_ZONES

    if args.mode == "demo":
        run_demo(zones, H)
    elif args.mode == "mouse":
        run_mouse(zones, H)
    elif args.mode == "live":
        run_live(zones, H)
