"""
zone_detector.py — 위험구역 판별 알고리즘

핵심 구조:
    각 구역은 inner_polygon(진입구역) + outer_polygon(경계구역) 두 면으로 구성
    판별 순서: inner 안 → inside / outer 안 → boundary / 둘 다 밖 → outside

    ※ 선(거리) 기준이 아니라 면(폴리곤) 기준으로 판별하므로
       구역 내부에서 항상 정확한 상태 유지
    ※ Homography 없이 픽셀 좌표 직접 사용 (시연용)
"""

import time

# ────────────────────────────────────────────────────────
# 위험구역 정의
#
# inner_polygon : 실제 위험구역 (진입 시 → inside)
# outer_polygon : 경계구역     (진입 시 → boundary)
#                 inner보다 바깥쪽으로 확장된 면
#
# 좌표 설정 방법:
#   1. OpenCV 창에서 구역 꼭짓점을 마우스로 클릭해서 픽셀 좌표 확인
#   2. inner_polygon 에 실제 위험선 좌표 입력
#   3. outer_polygon 에 경계선 좌표 입력 (inner보다 40~60px 바깥)
# ────────────────────────────────────────────────────────


# ──────────────────────────────────────────────────────────────
# ※ 좌표 단위 안내
#
# Homography 캘리브레이션을 한 경우:
#   → 좌표 단위 = cm (실제 바닥 기준)
#   → python main.py --mode setzone 으로 탑뷰에서 직접 클릭 설정
#   → 설정 후 danger_zones.json 에 자동 저장되므로 아래 값 수정 불필요
#
# 캘리브레이션 없이 픽셀 직접 사용하는 경우:
#   → 좌표 단위 = 픽셀 (카메라 화면 기준)
#   → 아래 값을 카메라 화면 픽셀 좌표로 직접 수정
# ──────────────────────────────────────────────────────────────

DANGER_ZONES = [
    {
        "id": 1,
        "name": "1구역 (크레인 반경)",
        # inner: 실제 위험구역 경계 (cm 또는 픽셀)
        "inner_polygon": [(80, 60),  (280, 60),  (280, 220), (80, 220)],
        # outer: 경계 감지 구역 (inner보다 50cm/px 바깥)
        "outer_polygon": [(30, 10),  (330, 10),  (330, 270), (30, 270)],
    },
    {
        "id": 2,
        "name": "2구역 (자재 낙하 위험)",
        "inner_polygon": [(320, 60),  (480, 60),  (480, 220), (320, 220)],
        "outer_polygon": [(270, 10),  (530, 10),  (530, 270), (270, 270)],
    },
]


# ────────────────────────────────────────────────────────
# Ray Casting — 점이 폴리곤 안에 있는지 판별
# ────────────────────────────────────────────────────────

def point_in_polygon(point, polygon):
    """
    Ray Casting 알고리즘
    반환: True(내부) / False(외부 또는 경계선)
    """
    x, y = point
    inside = False
    px, py = polygon[-1]
    for qx, qy in polygon:
        if ((py > y) != (qy > y)) and (x < (qx - px) * (y - py) / (qy - py) + px):
            inside = not inside
        px, py = qx, qy
    return inside


# ────────────────────────────────────────────────────────
# 단일 구역 판별
# ────────────────────────────────────────────────────────

def get_zone_status(point, zone):
    """
    판별 순서 (중요: inner 먼저 체크해야 내부에서 항상 inside 유지)

        inner 안  →  "inside"   (진입구역 진입)
        outer 안  →  "boundary" (경계구역 진입)
        둘 다 밖  →  "outside"  (안전)
    """
    if point_in_polygon(point, zone["inner_polygon"]):
        return "inside"
    if point_in_polygon(point, zone["outer_polygon"]):
        return "boundary"
    return "outside"


# ────────────────────────────────────────────────────────
# 전체 구역 순회 판별
# ────────────────────────────────────────────────────────

def check_all_zones(point, zones=DANGER_ZONES):
    """
    모든 위험구역 판별 후 가장 위험한 상태 반환

    Args:
        point: (x, y) 픽셀 좌표 (발 위치)

    Returns:
        {
            "point": (x, y),
            "results": [{"zone_id", "zone_name", "status"}, ...],
            "most_critical": "inside" | "boundary" | "outside",
            "critical_zone": "구역 이름" | None,
            "timestamp": float
        }
    """
    results = []
    most_critical = "outside"
    critical_zone = None
    priority = {"inside": 2, "boundary": 1, "outside": 0}

    for zone in zones:
        status = get_zone_status(point, zone)
        results.append({
            "zone_id":   zone["id"],
            "zone_name": zone["name"],
            "status":    status,
        })
        if priority[status] > priority[most_critical]:
            most_critical = status
            critical_zone = zone["name"]

    return {
        "point":         point,
        "results":       results,
        "most_critical": most_critical,
        "critical_zone": critical_zone,
        "timestamp":     time.time(),
    }
