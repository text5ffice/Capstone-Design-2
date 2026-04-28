"""
homography.py — 카메라 픽셀 좌표 → 실제 바닥 좌표 변환

캘리브레이션 방법:
    1. 바닥에 테이프로 4점 표시 (실제 크기 측정해둘 것)
    2. python main.py --mode calib 실행
    3. 카메라 영상에서 4점을 시계방향으로 클릭
    4. 실제 크기(cm) 입력
    5. homography_matrix.json 자동 저장 → 이후 자동 로드

폴리곤 좌표 설정 방법:
    캘리브레이션 후 python main.py --mode setzone 실행
    → 변환된 탑뷰 화면에서 위험구역 꼭짓점 클릭
"""

import cv2
import numpy as np
import json
import os

CALIB_FILE = "homography_matrix.json"
ZONE_FILE  = "danger_zones.json"


# ────────────────────────────────────────
# 변환 행렬 저장 / 로드
# ────────────────────────────────────────

def save_homography(H):
    with open(CALIB_FILE, "w") as f:
        json.dump(H.tolist(), f, indent=2)
    print(f"[Homography] 저장 완료 → {CALIB_FILE}")


def load_homography():
    if not os.path.exists(CALIB_FILE):
        return None
    with open(CALIB_FILE) as f:
        H = np.float32(json.load(f))
    print(f"[Homography] 로드 완료 ← {CALIB_FILE}")
    return H


# ────────────────────────────────────────
# 픽셀 ↔ 바닥 좌표 변환
# ────────────────────────────────────────

def pixel_to_floor(pixel_point, H):
    """발 위치 픽셀 좌표 → 실제 바닥 좌표(cm)"""
    pt = np.float32([[pixel_point]])
    result = cv2.perspectiveTransform(pt, H)
    return (float(result[0][0][0]), float(result[0][0][1]))


def floor_to_pixel(floor_point, H):
    """바닥 좌표(cm) → 픽셀 좌표 역변환 (시각화용)"""
    H_inv = np.linalg.inv(H)
    pt = np.float32([[floor_point]])
    result = cv2.perspectiveTransform(pt, H_inv)
    return (int(result[0][0][0]), int(result[0][0][1]))


# ────────────────────────────────────────
# 캘리브레이션 — 카메라 영상에서 4점 클릭
# ────────────────────────────────────────

def calibrate_from_camera(cap):
    """
    카메라 영상에서 바닥 4점 클릭 → Homography 행렬 계산 및 저장

    클릭 순서: 좌상단 → 우상단 → 우하단 → 좌하단 (시계 방향)

    Args:
        cap: cv2.VideoCapture 객체
    Returns:
        H: Homography 행렬 (취소 시 None)
    """
    WIN = "캘리브레이션 — 바닥 4점 시계방향 클릭 | Enter: 완료 | ESC: 취소"
    points = []

    def on_click(event, x, y, flags, param):
        if event == cv2.EVENT_LBUTTONDOWN and len(points) < 4:
            points.append((x, y))
            labels = ["좌상단", "우상단", "우하단", "좌하단"]
            print(f"  [{len(points)}] {labels[len(points)-1]}: ({x}, {y})")

    cv2.namedWindow(WIN)
    cv2.setMouseCallback(WIN, on_click)

    print("\n[캘리브레이션]")
    print("바닥에 표시한 4점을 시계방향으로 클릭하세요")
    print("순서: 좌상단 → 우상단 → 우하단 → 좌하단\n")

    while True:
        ret, frame = cap.read()
        if not ret:
            break
        display = frame.copy()

        # 클릭 점 표시
        colors = [(0,255,0), (0,200,255), (255,100,0), (200,0,255)]
        labels_short = ["1:좌상", "2:우상", "3:우하", "4:좌하"]
        for i, pt in enumerate(points):
            cv2.circle(display, pt, 8, colors[i], -1)
            cv2.putText(display, labels_short[i], (pt[0]+10, pt[1]-8),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, colors[i], 2)

        # 연결선
        if len(points) >= 2:
            for i in range(len(points)-1):
                cv2.line(display, points[i], points[i+1], (255,255,0), 1)
        if len(points) == 4:
            cv2.line(display, points[3], points[0], (255,255,0), 1)

        # 안내
        n = 4 - len(points)
        guide = f"남은 클릭: {n}  |  Enter: 완료  ESC: 취소" if n > 0 else "Enter 키로 완료"
        cv2.putText(display, guide, (10, display.shape[0]-15),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (200,200,200), 1)

        cv2.imshow(WIN, display)
        key = cv2.waitKey(1) & 0xFF

        if key == 13 and len(points) == 4:   # Enter
            break
        if key == 27:                          # ESC
            cv2.destroyWindow(WIN)
            return None

    cv2.destroyWindow(WIN)

    # 실제 크기 입력
    print("\n바닥 4점의 실제 크기를 입력하세요 (cm)")
    try:
        w = float(input("  가로 (좌상 → 우상, cm): "))
        h = float(input("  세로 (좌상 → 좌하, cm): "))
    except ValueError:
        print("  입력 오류 → 기본값 500×300cm 사용")
        w, h = 500.0, 300.0

    # 바닥 좌표계 (cm 기준 직사각형)
    floor_pts  = np.float32([[0,0],[w,0],[w,h],[0,h]])
    camera_pts = np.float32(points)

    H, _ = cv2.findHomography(camera_pts, floor_pts)
    save_homography(H)
    print(f"\n캘리브레이션 완료 ({w:.0f}cm × {h:.0f}cm)")
    return H


# ────────────────────────────────────────
# 위험구역 설정 — 탑뷰에서 클릭
# ────────────────────────────────────────

def set_zones_interactive(cap, H):
    """
    탑뷰(Bird's Eye View)로 변환된 화면에서
    마우스 클릭으로 위험구역 폴리곤 설정

    조작법:
        클릭      : 꼭짓점 추가
        Enter     : 현재 구역 완료 → 다음 구역으로
        Backspace : 마지막 점 취소
        ESC       : 저장 후 종료

    Returns:
        zones: 저장된 구역 리스트
    """
    WIN = "위험구역 설정 (탑뷰) | 클릭: 꼭짓점 | Enter: 구역완료 | ESC: 저장종료"

    ret, frame = cap.read()
    if not ret:
        return []

    fh, fw = frame.shape[:2]

    # 탑뷰 출력 크기 계산
    corners = np.float32([[0,0],[fw,0],[fw,fh],[0,fh]]).reshape(-1,1,2)
    tf = cv2.perspectiveTransform(corners, H)
    TOP_W = min(int(np.max(tf[:,:,0])) + 10, 900)
    TOP_H = min(int(np.max(tf[:,:,1])) + 10, 700)

    zones = []
    current_pts = []
    zone_idx = [1]
    mouse = [0, 0]

    def on_mouse(event, x, y, flags, param):
        mouse[0], mouse[1] = x, y
        if event == cv2.EVENT_LBUTTONDOWN:
            current_pts.append((x, y))
            print(f"  점 추가: ({x}, {y}) cm")

    cv2.namedWindow(WIN)
    cv2.setMouseCallback(WIN, on_mouse)

    COLORS = [(0,0,220),(0,165,255),(0,200,80),(200,180,0)]
    EXPAND_CM = 50  # 경계구역 확장 (cm)

    print(f"\n[위험구역 설정] {zone_idx[0]}구역 꼭짓점을 클릭하세요 (단위: cm)")

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        # 탑뷰 변환
        top = cv2.warpPerspective(frame, H, (TOP_W, TOP_H))

        # 완성된 구역 그리기
        for i, zone in enumerate(zones):
            c = COLORS[i % len(COLORS)]
            inner = np.array(zone["inner_polygon"], dtype=np.int32)
            outer = np.array(zone["outer_polygon"], dtype=np.int32)
            overlay = top.copy()
            cv2.fillPoly(overlay, [outer], c)
            cv2.addWeighted(overlay, 0.08, top, 0.92, 0, top)
            overlay = top.copy()
            cv2.fillPoly(overlay, [inner], c)
            cv2.addWeighted(overlay, 0.22, top, 0.78, 0, top)
            cv2.polylines(top, [outer], True, c, 1)
            cv2.polylines(top, [inner], True, c, 2)
            cx = int(np.mean([p[0] for p in zone["inner_polygon"]]))
            cy = int(np.mean([p[1] for p in zone["inner_polygon"]]))
            cv2.putText(top, zone["name"], (cx-40, cy),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255,255,255), 1)

        # 현재 그리는 중
        c_cur = COLORS[len(zones) % len(COLORS)]
        for pt in current_pts:
            cv2.circle(top, pt, 5, c_cur, -1)
        if len(current_pts) >= 2:
            for i in range(len(current_pts)-1):
                cv2.line(top, current_pts[i], current_pts[i+1], c_cur, 1)
        if current_pts:
            cv2.line(top, current_pts[-1], tuple(mouse), c_cur, 1, cv2.LINE_AA)

        # 안내
        guide = (f"{zone_idx[0]}구역 | 점:{len(current_pts)}개 | "
                 f"Enter:구역완료(3점이상) Back:점취소 ESC:저장종료")
        cv2.putText(top, guide, (10, TOP_H-12),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.38, (180,180,180), 1)

        # cm 좌표 표시
        cv2.putText(top, f"({mouse[0]}, {mouse[1]}) cm",
                    (mouse[0]+10, mouse[1]-10),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.38, (200,200,100), 1)

        cv2.imshow(WIN, top)
        key = cv2.waitKey(30) & 0xFF

        if key == 13 and len(current_pts) >= 3:   # Enter
            name = input(f"  {zone_idx[0]}구역 이름 (예: 크레인반경): ").strip() or f"{zone_idx[0]}구역"

            # outer: inner 꼭짓점을 EXPAND_CM만큼 바깥으로 확장
            cx = np.mean([p[0] for p in current_pts])
            cy = np.mean([p[1] for p in current_pts])
            outer = []
            for (px, py) in current_pts:
                dx, dy = px - cx, py - cy
                d = max(np.hypot(dx, dy), 1)
                outer.append((int(px + dx/d*EXPAND_CM), int(py + dy/d*EXPAND_CM)))

            zones.append({
                "id": zone_idx[0],
                "name": name,
                "inner_polygon": current_pts.copy(),
                "outer_polygon": outer,
            })
            print(f"  → '{name}' 저장 (inner {len(current_pts)}점, outer 자동생성)")
            current_pts.clear()
            zone_idx[0] += 1
            print(f"\n[{zone_idx[0]}구역] 계속 클릭하거나 ESC로 종료")

        elif key == 8 and current_pts:   # Backspace
            print(f"  취소: {current_pts.pop()}")

        elif key == 27:   # ESC
            break

    cv2.destroyWindow(WIN)

    if zones:
        with open(ZONE_FILE, "w", encoding="utf-8") as f:
            json.dump(zones, f, ensure_ascii=False, indent=2)
        print(f"\n위험구역 {len(zones)}개 저장 → {ZONE_FILE}")

        print("\n=== zone_detector.py DANGER_ZONES 복사용 ===")
        print("DANGER_ZONES = [")
        for z in zones:
            print(f"    {{\"id\":{z['id']}, \"name\":\"{z['name']}\",")
            print(f"     \"inner_polygon\":{z['inner_polygon']},")
            print(f"     \"outer_polygon\":{z['outer_polygon']}}},")
        print("]")

    return zones


# ────────────────────────────────────────
# 저장된 구역 로드
# ────────────────────────────────────────

def load_zones():
    if not os.path.exists(ZONE_FILE):
        return None
    with open(ZONE_FILE, encoding="utf-8") as f:
        zones = json.load(f)
    for z in zones:
        z["inner_polygon"] = [tuple(p) for p in z["inner_polygon"]]
        z["outer_polygon"] = [tuple(p) for p in z["outer_polygon"]]
    print(f"[Zone] {len(zones)}개 구역 로드 ← {ZONE_FILE}")
    return zones
