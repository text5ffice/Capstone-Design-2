"""
yolo_dummy.py — YOLO 결과 더미 시뮬레이터

AI팀 YOLO 모델이 완성되기 전까지 이 파일로 테스트
YOLO 연결 시 → yolo_real.py 로 교체, 나머지 코드 변경 없음

YOLO가 실제로 반환하는 형식:
    [
        {
            "worker_id": "worker_01",
            "bbox": (x1, y1, x2, y2),   # bounding box
            "confidence": 0.92,
            "foot_pixel": (cx, y2)       # 발 위치 = bbox 하단 중심
        },
        ...
    ]
"""

import math
import time
import random


# ────────────────────────────────────────
# 더미 작업자 경로 정의
# ────────────────────────────────────────

DUMMY_PATHS = {
    "worker_01": [
        # (frame, x, y) — 카메라 픽셀 기준 이동 경로
        (0,   330, 380),
        (30,  280, 340),
        (60,  200, 300),   # 1구역 근처
        (90,  140, 200),   # 1구역 경계
        (120, 180, 160),   # 1구역 내부!
        (150, 180, 160),
        (180, 280, 280),   # 이탈
        (210, 400, 280),
        (240, 480, 250),   # 2구역 근처
        (270, 510, 220),   # 2구역 경계
        (300, 530, 280),   # 2구역 내부!
        (330, 530, 280),
        (360, 400, 350),   # 이탈
        (390, 330, 380),   # 안전
    ],
    "worker_02": [
        (0,   550, 400),
        (60,  560, 300),
        (120, 560, 300),
        (180, 400, 350),
        (240, 330, 380),
        (300, 330, 380),
    ],
}

# bounding box 크기 (더미용 고정값)
BBOX_W = 60
BBOX_H = 120


# ────────────────────────────────────────
# 경로 보간 (프레임 사이 위치 계산)
# ────────────────────────────────────────

def _interpolate(path, frame_idx):
    """두 keyframe 사이 위치를 선형 보간"""
    frames = [p[0] for p in path]
    if frame_idx <= frames[0]:
        return path[0][1], path[0][2]
    if frame_idx >= frames[-1]:
        return path[-1][1], path[-1][2]

    for i in range(len(frames) - 1):
        f0, f1 = frames[i], frames[i + 1]
        if f0 <= frame_idx <= f1:
            t = (frame_idx - f0) / (f1 - f0)
            x = path[i][1] + t * (path[i + 1][1] - path[i][1])
            y = path[i][2] + t * (path[i + 1][2] - path[i][2])
            # 미세 떨림 추가 (실제 감지처럼 보이게)
            x += random.uniform(-1.5, 1.5)
            y += random.uniform(-1.5, 1.5)
            return x, y

    return path[-1][1], path[-1][2]


# ────────────────────────────────────────
# 더미 YOLO 결과 반환 함수
# (실제 YOLO 연결 시 이 함수만 교체)
# ────────────────────────────────────────

def get_detections(frame_idx):
    """
    현재 프레임에서 감지된 작업자 목록 반환

    Returns:
        list of dict:
            worker_id    : 작업자 ID
            bbox         : (x1, y1, x2, y2) bounding box 픽셀 좌표
            confidence   : 감지 신뢰도
            foot_pixel   : (cx, y2) 발 위치 픽셀 좌표  ← 핵심 좌표
    """
    detections = []

    for worker_id, path in DUMMY_PATHS.items():
        max_frame = path[-1][0]
        if frame_idx > max_frame + 30:
            continue  # 경로 끝난 작업자는 제외

        cx, cy = _interpolate(path, frame_idx)

        x1 = cx - BBOX_W // 2
        y1 = cy - BBOX_H
        x2 = cx + BBOX_W // 2
        y2 = cy

        foot_x = (x1 + x2) / 2   # bbox 하단 중심 x
        foot_y = y2               # bbox 하단 y

        detections.append({
            "worker_id": worker_id,
            "bbox": (int(x1), int(y1), int(x2), int(y2)),
            "confidence": round(random.uniform(0.88, 0.97), 2),
            "foot_pixel": (float(foot_x), float(foot_y)),
        })

    return detections


# ────────────────────────────────────────
# 실제 YOLO 연결 시 교체할 함수 (참고용)
# ────────────────────────────────────────

"""
# yolo_real.py (AI팀 완성 후 이 파일로 교체)

from ultralytics import YOLO

model = YOLO("best.pt")  # 학습된 모델

def get_detections(frame):
    results = model(frame)[0]
    detections = []

    for i, box in enumerate(results.boxes):
        x1, y1, x2, y2 = map(int, box.xyxy[0])
        conf = float(box.conf[0])

        foot_x = (x1 + x2) / 2
        foot_y = y2

        detections.append({
            "worker_id": f"worker_{i+1:02d}",
            "bbox": (x1, y1, x2, y2),
            "confidence": round(conf, 2),
            "foot_pixel": (foot_x, foot_y),
        })

    return detections
"""
