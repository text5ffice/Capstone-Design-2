"""
zone_setup.py — 라이브 카메라 화면에서 클릭으로 위험구역 설정 (1280x720 와이드 버전)
"""

import cv2
import numpy as np
import json
import os
import argparse

ZONE_FILE = "danger_zones.json"
FONT = cv2.FONT_HERSHEY_SIMPLEX

# 🚀 해상도 설정 (app.py와 완벽하게 동일하게 맞춤!)
SCREEN_W = 1280
SCREEN_H = 720

ZONE_COLORS = [
    (74,  75,  226),   # 빨강 (BGR)
    (221, 138, 55),    # 파랑
    (75,  158, 29),    # 초록
    (30,  85,  216),   # 주황
    (221, 119, 127),   # 보라
]
BUFFER_PX = 45  # 주의구역 확장 픽셀

def expand_polygon(pts, d):
    arr = np.array(pts, dtype=np.float32)
    cx, cy = arr.mean(axis=0)
    result = []
    for (px, py) in arr:
        dx, dy = px - cx, py - cy
        dist = max(np.hypot(dx, dy), 1)
        result.append((int(px + dx/dist*d), int(py + dy/dist*d)))
    return result

def save_zones(zones):
    data = []
    for z in zones:
        data.append({
            "id":            z["id"],
            "name":          z["name"],
            "inner_polygon": z["inner"],
            "outer_polygon": z["outer"],
        })
    with open(ZONE_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"[저장] {len(zones)}개 구역 → {ZONE_FILE}")

def load_zones():
    if not os.path.exists(ZONE_FILE):
        return []
    with open(ZONE_FILE, encoding="utf-8") as f:
        data = json.load(f)
    zones = []
    for z in data:
        zones.append({
            "id":    z["id"],
            "name":  z["name"],
            "inner": [tuple(p) for p in z["inner_polygon"]],
            "outer": [tuple(p) for p in z["outer_polygon"]],
        })
    print(f"[로드] {len(zones)}개 구역 ← {ZONE_FILE}")
    return zones

def draw_zones(frame, zones, highlight_id=None):
    overlay = frame.copy()
    for i, zone in enumerate(zones):
        color = ZONE_COLORS[i % len(ZONE_COLORS)]
        inner_pts = np.array(zone["inner"], dtype=np.int32)
        outer_pts = np.array(zone["outer"], dtype=np.int32)

        is_highlight = (zone["id"] == highlight_id)

        outer_alpha = 0.12 if not is_highlight else 0.20
        cv2.fillPoly(overlay, [outer_pts], (30, 100, 180))
        cv2.addWeighted(overlay, outer_alpha, frame, 1-outer_alpha, 0, frame)
        cv2.polylines(frame, [outer_pts], True, (100, 150, 230), 1, cv2.LINE_AA)

        overlay = frame.copy()
        inner_alpha = 0.15 if not is_highlight else 0.28
        cv2.fillPoly(overlay, [inner_pts], color)
        cv2.addWeighted(overlay, inner_alpha, frame, 1-inner_alpha, 0, frame)
        inner_thick = 2 if is_highlight else 1
        cv2.polylines(frame, [inner_pts], True, color, inner_thick, cv2.LINE_AA)

        cx = int(np.mean([p[0] for p in zone["inner"]]))
        cy = int(np.mean([p[1] for p in zone["inner"]]))
        cv2.putText(frame, zone["name"], (cx-50, cy-6), FONT, 0.45, (255,255,255), 1, cv2.LINE_AA)
        cv2.putText(frame, "[ 위험 ]", (cx-28, cy+12), FONT, 0.36, (180,120,120), 1, cv2.LINE_AA)
        cv2.circle(frame, (cx, cy-30), 12, color, -1)
        cv2.putText(frame, str(zone["id"]), (cx-5, cy-25), FONT, 0.45, (255,255,255), 1, cv2.LINE_AA)

def draw_current(frame, current_pts, mouse_pos, zone_idx, buf):
    if not current_pts:
        return
    color = ZONE_COLORS[zone_idx % len(ZONE_COLORS)]
    pts = current_pts

    if len(pts) >= 3:
        preview_outer = expand_polygon(pts, buf)
        outer_arr = np.array(preview_outer, dtype=np.int32)
        overlay = frame.copy()
        cv2.fillPoly(overlay, [outer_arr], (30, 100, 180))
        cv2.addWeighted(overlay, 0.10, frame, 0.90, 0, frame)
        cv2.polylines(frame, [outer_arr], True, (100, 150, 230), 1, cv2.LINE_AA)

        inner_arr = np.array(pts, dtype=np.int32)
        overlay = frame.copy()
        cv2.fillPoly(overlay, [inner_arr], color)
        cv2.addWeighted(overlay, 0.20, frame, 0.80, 0, frame)

    for i in range(len(pts)-1):
        cv2.line(frame, pts[i], pts[i+1], color, 1, cv2.LINE_AA)
    if len(pts) >= 3:
        cv2.line(frame, pts[-1], mouse_pos, color, 1, cv2.LINE_AA)
        cv2.line(frame, mouse_pos, pts[0], (100,100,100), 1, cv2.LINE_AA)
    else:
        cv2.line(frame, pts[-1], mouse_pos, color, 1, cv2.LINE_AA)

    for i, pt in enumerate(pts):
        cv2.circle(frame, pt, 6, color, -1, cv2.LINE_AA)
        cv2.circle(frame, pt, 8, (255,255,255), 1, cv2.LINE_AA)
        cv2.putText(frame, str(i+1), (pt[0]-4, pt[1]+5), FONT, 0.35, (255,255,255), 1, cv2.LINE_AA)

def draw_ui(frame, zones, current_pts, mouse_pos, buf):
    h, w = frame.shape[:2]
    overlay = frame.copy()
    cv2.rectangle(overlay, (0,0), (w, 48), (15,15,20), -1)
    cv2.addWeighted(overlay, 0.75, frame, 0.25, 0, frame)

    if current_pts:
        state = f"그리는 중: {len(current_pts)}개 점  |  Enter: 저장  Back: 점취소  ESC: 완료"
        cv2.putText(frame, state, (10, 20), FONT, 0.45, (100, 200, 255), 1)
    else:
        state = f"구역 {len(zones)}개 설정됨  |  클릭: 새 구역 시작  D: 마지막삭제  R: 초기화  ESC: 저장종료"
        cv2.putText(frame, state, (10, 20), FONT, 0.45, (180, 220, 180), 1)

    cv2.putText(frame, f"({mouse_pos[0]}, {mouse_pos[1]})", (10, 40), FONT, 0.36, (120,120,120), 1)
    cv2.putText(frame, f"주의구역 확장: {buf}px  (+/-로 조절)", (w - 250, 20), FONT, 0.4, (180, 160, 100), 1)

    overlay = frame.copy()
    cv2.rectangle(overlay, (0, h-36), (w, h), (15,15,20), -1)
    cv2.addWeighted(overlay, 0.75, frame, 0.25, 0, frame)

    cv2.rectangle(frame, (10, h-26), (30, h-14), (74,75,226), -1)
    cv2.putText(frame, "위험구역", (34, h-14), FONT, 0.38, (200,180,180), 1)

    cv2.rectangle(frame, (110, h-26), (130, h-14), (30,100,180), -1)
    cv2.putText(frame, "주의구역", (134, h-14), FONT, 0.38, (180,200,220), 1)

def run_setup(cap, dummy_mode=False):
    WIN = "위험구역 설정 — 클릭으로 꼭짓점 추가 | Enter: 구역저장 | ESC: 완료"
    cv2.namedWindow(WIN)
    zones = load_zones()
    current_pts = []
    mouse_pos = [0, 0]
    buf = BUFFER_PX

    def on_mouse(event, x, y, flags, param):
        mouse_pos[0], mouse_pos[1] = x, y
        if event == cv2.EVENT_LBUTTONDOWN:
            current_pts.append((x, y))

    cv2.setMouseCallback(WIN, on_mouse)

    dummy_bg = None
    if dummy_mode:
        dummy_bg = np.zeros((SCREEN_H, SCREEN_W, 3), dtype=np.uint8)
        dummy_bg[:] = (22, 24, 32)
        for x in range(0, SCREEN_W, 40):
            cv2.line(dummy_bg, (x,0), (x,SCREEN_H), (35,35,45), 1)
        for y in range(0, SCREEN_H, 40):
            cv2.line(dummy_bg, (0,y), (SCREEN_W,y), (35,35,45), 1)
        cv2.putText(dummy_bg, "카메라 더미 배경 (실제 카메라 연결 시 영상으로 교체됨)", (40, SCREEN_H-20), FONT, 0.4, (60,60,80), 1)

    print(f"\n[위험구역 설정 시작]")
    while True:
        if dummy_mode:
            frame = dummy_bg.copy()
        else:
            ret, frame = cap.read()
            if not ret: break
            frame = cv2.resize(frame, (SCREEN_W, SCREEN_H)) # 🚀 여기서 와이드로 펴줍니다.

        mp = tuple(mouse_pos)
        draw_zones(frame, zones)
        draw_current(frame, current_pts, mp, len(zones), buf)
        draw_ui(frame, zones, current_pts, mp, buf)

        cv2.imshow(WIN, frame)
        key = cv2.waitKey(30) & 0xFF

        if key == 13 and len(current_pts) >= 3:
            name = input(f"  {len(zones)+1}구역 이름 (예: 크레인반경, 엔터=기본이름): ").strip()
            if not name: name = f"{len(zones)+1}구역"
            outer = expand_polygon(current_pts, buf)
            zones.append({"id": len(zones)+1, "name": name, "inner": current_pts.copy(), "outer": outer})
            current_pts.clear()
        elif key == 8 and current_pts: current_pts.pop()
        elif key == ord('d') or key == ord('D'): 
            if zones: zones.pop()
        elif key == ord('r') or key == ord('R'):
            zones.clear()
            current_pts.clear()
        elif key == ord('+') or key == ord('='): buf = min(buf + 5, 120)
        elif key == ord('-'): buf = max(buf - 5, 10)
        elif key == 27: break

    cv2.destroyWindow(WIN)
    if zones:
        save_zones(zones)
        print(f"\n설정 완료! app.py 실행 시 자동으로 불러옵니다.")
    return zones

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--dummy", action="store_true", help="카메라 없이 더미 배경으로 테스트")
    args = parser.parse_args()

    if args.dummy:
        run_setup(None, dummy_mode=True)
    else:
        cap = cv2.VideoCapture(0)
        if not cap.isOpened():
            print("카메라 연결 실패 → 더미 모드로 실행합니다")
            run_setup(None, dummy_mode=True)
        else:
            run_setup(cap)
            cap.release()