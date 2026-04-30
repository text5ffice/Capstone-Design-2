# ===== 넘어짐 감지 시스템 v2 (Google Colab용) =====
# YOLO-pose 모델로 사람의 자세를 분석해서 넘어졌는지 판단
# v2: 정면→뒤로 넘어지는 경우도 감지하도록 기준 추가
#
# [실행 환경] Google Colab (GPU 런타임 권장)
# [실행 방법] 셀 하나씩 순서대로 실행

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 셀 1: 라이브러리 설치
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# !pip install ultralytics

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 셀 2: 모델 로드
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
from ultralytics import YOLO
import cv2
import numpy as np
import os
import math
from datetime import datetime

model = YOLO('yolov8m-pose.pt')
print("모델 로드 완료!")

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 셀 3: 넘어짐 판단 함수들
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# YOLO-pose 키포인트 인덱스 (사람 몸의 각 부위 번호)
# 0:코  1:왼눈  2:오른눈  3:왼귀  4:오른귀
# 5:왼어깨  6:오른어깨  7:왼팔꿈치  8:오른팔꿈치
# 9:왼손목  10:오른손목  11:왼엉덩이  12:오른엉덩이
# 13:왼무릎  14:오른무릎  15:왼발목  16:오른발목

def calculate_angle(point1, point2):
    """두 점 사이의 각도 계산 (수직 기준)"""
    dx = point2[0] - point1[0]
    dy = point2[1] - point1[1]
    angle = abs(math.degrees(math.atan2(dx, dy)))
    return angle


def is_fallen(keypoints, bbox, prev_height=None, confidence_threshold=0.5):
    """
    넘어짐 판단 로직 (5가지 기준을 종합)
    
    [판단 기준]
    1. 바운딩 박스 비율: 가로/세로 > 1.2 이면 누워있을 가능성 (옆으로 넘어짐)
    2. 어깨-엉덩이 각도: 몸통이 45도 이상 기울면 넘어짐
    3. 머리 위치: 머리가 엉덩이보다 아래에 있으면 넘어짐
    4. 급격한 높이 변화: 이전 프레임 대비 높이가 40% 이상 줄면 넘어지는 중 (앞뒤로 넘어짐)
    5. 키포인트 수직 압축: 머리~발 간격이 좁아지면 쓰러지는 중 (앞뒤로 넘어짐)
    
    Returns: (넘어짐 여부, 확신도, 판단 이유)
    """
    kp = keypoints  # keypoints 배열 (17, 3) → [x, y, confidence]
    
    # 키포인트 신뢰도 체크
    nose = kp[0] if kp[0][2] > confidence_threshold else None
    l_shoulder = kp[5] if kp[5][2] > confidence_threshold else None
    r_shoulder = kp[6] if kp[6][2] > confidence_threshold else None
    l_hip = kp[11] if kp[11][2] > confidence_threshold else None
    r_hip = kp[12] if kp[12][2] > confidence_threshold else None
    l_knee = kp[13] if kp[13][2] > confidence_threshold else None
    r_knee = kp[14] if kp[14][2] > confidence_threshold else None
    l_ankle = kp[15] if kp[15][2] > confidence_threshold else None
    r_ankle = kp[16] if kp[16][2] > confidence_threshold else None
    
    fall_score = 0  # 넘어짐 점수 (높을수록 넘어졌을 가능성)
    reasons = []
    
    # ── 기준 1: 바운딩 박스 가로/세로 비율 (옆으로 넘어짐) ──
    x1, y1, x2, y2 = bbox
    width = x2 - x1
    height = y2 - y1
    
    if height > 0:
        aspect_ratio = width / height
        if aspect_ratio > 1.2:
            fall_score += 40
            reasons.append(f"박스비율({aspect_ratio:.1f})")
        elif aspect_ratio > 0.9:
            fall_score += 15
    
    # ── 기준 2: 몸통 기울기 (어깨 중심 → 엉덩이 중심 각도) ──
    if l_shoulder is not None and r_shoulder is not None and \
       l_hip is not None and r_hip is not None:
        
        shoulder_center = [
            (l_shoulder[0] + r_shoulder[0]) / 2,
            (l_shoulder[1] + r_shoulder[1]) / 2
        ]
        hip_center = [
            (l_hip[0] + r_hip[0]) / 2,
            (l_hip[1] + r_hip[1]) / 2
        ]
        
        body_angle = calculate_angle(shoulder_center, hip_center)
        
        if body_angle > 50:
            fall_score += 40
            reasons.append(f"몸통기울기({body_angle:.0f}도)")
        elif body_angle > 30:
            fall_score += 20
            reasons.append(f"기울어짐({body_angle:.0f}도)")
    
    # ── 기준 3: 머리가 엉덩이보다 아래에 있는지 ──
    if nose is not None and l_hip is not None and r_hip is not None:
        hip_y = (l_hip[1] + r_hip[1]) / 2
        # y좌표는 아래로 갈수록 커지므로, 코의 y가 엉덩이 y보다 크면 머리가 아래
        if nose[1] > hip_y:
            fall_score += 30
            reasons.append("머리가엉덩이보다아래")
    
    # ── 기준 4: 급격한 높이 변화 (앞뒤로 넘어질 때 핵심!) ──
    # 이전 프레임의 높이와 비교해서 갑자기 줄어들면 넘어지는 중
    if prev_height is not None and prev_height > 0 and height > 0:
        height_ratio = height / prev_height
        if height_ratio < 0.6:  # 높이가 40% 이상 줄었으면
            fall_score += 35
            reasons.append(f"급격한높이감소({height_ratio:.2f})")
        elif height_ratio < 0.75:  # 25% 이상 줄었으면
            fall_score += 20
            reasons.append(f"높이감소({height_ratio:.2f})")
    
    # ── 기준 5: 키포인트 수직 압축 (앞뒤로 넘어질 때 핵심!) ──
    # 서 있으면 머리~발 간격이 크고, 쓰러지면 간격이 좁아짐
    if nose is not None and (l_ankle is not None or r_ankle is not None):
        ankle_y = l_ankle[1] if l_ankle is not None else r_ankle[1]
        vertical_span = abs(ankle_y - nose[1])
        box_height = y2 - y1
        
        if box_height > 0:
            span_ratio = vertical_span / box_height
            if span_ratio < 0.4:  # 머리~발 간격이 박스의 40% 미만
                fall_score += 30
                reasons.append(f"수직압축({span_ratio:.2f})")
            elif span_ratio < 0.55:
                fall_score += 15
                reasons.append(f"약간압축({span_ratio:.2f})")
    
    # ── 기준 6: 무릎이 엉덩이보다 위에 있는지 (뒤로 쓰러질 때) ──
    if l_hip is not None and r_hip is not None and \
       (l_knee is not None or r_knee is not None):
        hip_y = (l_hip[1] + r_hip[1]) / 2
        knee_y = l_knee[1] if l_knee is not None else r_knee[1]
        
        # 무릎이 엉덩이보다 위에 있으면 (y가 작으면 위) → 다리가 올라간 상태
        if knee_y < hip_y - 20:  # 20px 이상 차이
            fall_score += 25
            reasons.append("무릎이엉덩이위")
    
    # ── 최종 판단 ──
    is_fall = fall_score >= 60  # 60점 이상이면 넘어짐으로 판단
    
    return is_fall, fall_score, reasons


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 셀 4: 영상 분석 함수
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def analyze_video(video_path, output_path=None):
    """
    영상을 분석해서 넘어짐을 감지하고 결과 영상 저장
    
    [동작 방식]
    1. 영상을 프레임 단위로 읽기
    2. 각 프레임에서 YOLO-pose로 사람 감지
    3. 각 사람마다 넘어짐 판단 (이전 프레임 높이도 비교)
    4. 결과를 영상에 표시 (초록=정상, 빨강=넘어짐)
    """
    cap = cv2.VideoCapture(video_path)
    
    if not cap.isOpened():
        print(f"영상을 열 수 없습니다: {video_path}")
        return
    
    # 영상 정보
    fps = int(cap.get(cv2.CAP_PROP_FPS))
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    
    print(f"영상 정보: {width}x{height}, {fps}FPS, 총 {total_frames}프레임")
    
    # 출력 영상 설정
    if output_path is None:
        name = os.path.splitext(os.path.basename(video_path))[0]
        output_path = f'/content/fall_detection_{name}.mp4'
    
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(output_path, fourcc, fps, (width, height))
    
    fall_frames = []  # 넘어짐이 감지된 프레임 번호들
    frame_count = 0
    
    # ★ 이전 프레임의 높이 기억 (기준 4에서 사용)
    prev_heights = {}  # {사람인덱스: 이전높이}
    
    print("분석 시작...")
    
    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
        
        frame_count += 1
        
        # 2초마다 진행률 표시
        if frame_count % (fps * 2) == 0:
            progress = (frame_count / total_frames) * 100
            print(f"  진행: {progress:.0f}% ({frame_count}/{total_frames})")
        
        # YOLO-pose 실행
        results = model(frame, verbose=False, conf=0.3)
        
        current_heights = {}  # 이번 프레임의 높이 저장
        
        for result in results:
            if result.keypoints is None or result.boxes is None:
                continue
            
            keypoints_data = result.keypoints.data.cpu().numpy()
            boxes = result.boxes.xyxy.cpu().numpy()
            
            for i, (kp, box) in enumerate(zip(keypoints_data, boxes)):
                # 이전 프레임 높이 가져오기
                prev_h = prev_heights.get(i, None)
                
                # 현재 높이 저장
                x1, y1, x2, y2 = box
                current_h = y2 - y1
                current_heights[i] = current_h
                
                # 넘어짐 판단 (이전 높이도 전달)
                is_fall, score, reasons = is_fallen(kp, box, prev_height=prev_h)
                
                x1, y1, x2, y2 = map(int, box)
                
                if is_fall:
                    # ====== 넘어짐 감지!! ======
                    color = (0, 0, 255)  # 빨강
                    label = f"FALL! ({score})"
                    thickness = 3
                    
                    if frame_count not in fall_frames:
                        fall_frames.append(frame_count)
                        time_sec = frame_count / fps
                        print(f"  ⚠️ 넘어짐 감지! "
                              f"시간: {time_sec:.1f}초, "
                              f"점수: {score}, "
                              f"이유: {', '.join(reasons)}")
                else:
                    # ====== 정상 ======
                    color = (0, 255, 0)  # 초록
                    label = f"OK ({score})"
                    thickness = 2
                
                # 바운딩 박스 그리기
                cv2.rectangle(frame, (x1, y1), (x2, y2), color, thickness)
                
                # 라벨 배경 + 텍스트
                label_size = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.7, 2)[0]
                cv2.rectangle(frame, (x1, y1 - 30), (x1 + label_size[0] + 10, y1), color, -1)
                cv2.putText(frame, label, (x1 + 5, y1 - 8),
                           cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
                
                # 키포인트 (관절) 표시
                for j, point in enumerate(kp):
                    if point[2] > 0.5:  # 신뢰도 50% 이상만
                        px, py = int(point[0]), int(point[1])
                        cv2.circle(frame, (px, py), 4, color, -1)
                
                # 뼈대 연결선 그리기 (시각적으로 보기 좋게)
                skeleton = [
                    (5, 6), (5, 7), (7, 9), (6, 8), (8, 10),   # 상체
                    (5, 11), (6, 12), (11, 12),                  # 몸통
                    (11, 13), (13, 15), (12, 14), (14, 16),      # 하체
                ]
                for (a, b) in skeleton:
                    if kp[a][2] > 0.5 and kp[b][2] > 0.5:
                        pt1 = (int(kp[a][0]), int(kp[a][1]))
                        pt2 = (int(kp[b][0]), int(kp[b][1]))
                        cv2.line(frame, pt1, pt2, color, 2)
        
        # 이전 높이 업데이트
        prev_heights = current_heights
        
        out.write(frame)
    
    cap.release()
    out.release()
    
    # 결과 요약
    print("\n" + "=" * 50)
    print(f"분석 완료!")
    print(f"총 프레임: {total_frames}")
    print(f"넘어짐 감지 프레임: {len(fall_frames)}개")
    if fall_frames:
        print(f"넘어짐 발생 시간:")
        for f in fall_frames[:10]:  # 처음 10개만 표시
            print(f"  - {f/fps:.1f}초")
    print(f"결과 영상: {output_path}")
    print("=" * 50)
    
    return output_path, fall_frames


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 셀 5: 이미지 분석 함수 (사진 한 장용)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def analyze_image(image_path):
    """사진 한 장에서 넘어짐 감지"""
    frame = cv2.imread(image_path)
    if frame is None:
        print(f"이미지를 열 수 없습니다: {image_path}")
        return
    
    results = model(frame, verbose=False, conf=0.3)
    
    for result in results:
        if result.keypoints is None or result.boxes is None:
            print("사람이 감지되지 않았습니다.")
            continue
        
        keypoints_data = result.keypoints.data.cpu().numpy()
        boxes = result.boxes.xyxy.cpu().numpy()
        
        for i, (kp, box) in enumerate(zip(keypoints_data, boxes)):
            is_fall, score, reasons = is_fallen(kp, box)
            
            x1, y1, x2, y2 = map(int, box)
            
            if is_fall:
                color = (0, 0, 255)
                label = f"FALL! ({score})"
                print(f"⚠️ 사람 {i+1}: 넘어짐! 점수={score}, 이유={reasons}")
            else:
                color = (0, 255, 0)
                label = f"OK ({score})"
                print(f"✅ 사람 {i+1}: 정상. 점수={score}")
            
            cv2.rectangle(frame, (x1, y1), (x2, y2), color, 3)
            
            label_size = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.8, 2)[0]
            cv2.rectangle(frame, (x1, y1 - 35), (x1 + label_size[0] + 10, y1), color, -1)
            cv2.putText(frame, label, (x1 + 5, y1 - 10),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
            
            # 키포인트
            for j, point in enumerate(kp):
                if point[2] > 0.5:
                    px, py = int(point[0]), int(point[1])
                    cv2.circle(frame, (px, py), 5, color, -1)
            
            # 뼈대 연결선
            skeleton = [
                (5, 6), (5, 7), (7, 9), (6, 8), (8, 10),
                (5, 11), (6, 12), (11, 12),
                (11, 13), (13, 15), (12, 14), (14, 16),
            ]
            for (a, b) in skeleton:
                if kp[a][2] > 0.5 and kp[b][2] > 0.5:
                    pt1 = (int(kp[a][0]), int(kp[a][1]))
                    pt2 = (int(kp[b][0]), int(kp[b][1]))
                    cv2.line(frame, pt1, pt2, color, 2)
    
    output_path = '/content/fall_result.jpg'
    cv2.imwrite(output_path, frame)
    print(f"결과 이미지: {output_path}")
    
    # Colab에서 바로 표시
    from IPython.display import Image, display
    display(Image(output_path))
    
    return output_path


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 셀 6: 실행! (파일 업로드 후 분석)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

from google.colab import files

print("=" * 50)
print("  넘어짐 감지 시스템 v2")
print("  판단 기준: 박스비율 + 몸통기울기 + 머리위치")
print("           + 높이변화 + 수직압축 + 무릎위치")
print("=" * 50)
print("\n분석할 파일을 업로드하세요 (영상 또는 이미지)")

uploaded = files.upload()

for filename in uploaded.keys():
    ext = os.path.splitext(filename)[1].lower()
    
    if ext in ['.mp4', '.avi', '.mov', '.mkv', '.webm']:
        # 영상 분석
        print(f"\n영상 분석 시작: {filename}")
        output_path, fall_frames = analyze_video(filename)
        
        # 결과 다운로드
        print("\n결과 영상 다운로드 중...")
        files.download(output_path)
        
    elif ext in ['.jpg', '.jpeg', '.png', '.bmp']:
        # 이미지 분석
        print(f"\n이미지 분석: {filename}")
        analyze_image(filename)
    
    else:
        print(f"지원하지 않는 형식: {ext}")
