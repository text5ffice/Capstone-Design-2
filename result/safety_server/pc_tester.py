import cv2
import requests
import time

# 🚨 내 컴퓨터(로컬)에서 돌아가고 있는 서버 주소
SERVER_URL = 'http://127.0.0.1:5000/api/analyze_frame'

# =====================================================================
# 💡 테스트 모드 선택 (원하는 것의 주석을 풀고 사용하세요)
# =====================================================================
# 모드 1: 노트북 웹캠 사용 (내가 직접 카메라 앞에서 눕는 연기하기)
video_source = 0 

# 모드 2: 준비된 동영상 파일 사용 (유튜브 등에서 다운받은 넘어지는 영상)
# video_source = 'fall_test_video.mp4'  
# =====================================================================

cap = cv2.VideoCapture(video_source)

print("📷 테스트 카메라(또는 영상) 송신 시작...")

while cap.isOpened():
    ret, frame = cap.read()
    if not ret:
        print("영상 재생이 끝났거나 카메라를 읽을 수 없습니다.")
        break
        
    # 영상을 약간 줄여서 전송 속도 향상
    frame = cv2.resize(frame, (640, 480))
    
    # 이미지를 메모리상에서 jpeg로 압축
    _, img_encoded = cv2.imencode('.jpg', frame)
    
    files = {'image': ('frame.jpg', img_encoded.tobytes(), 'image/jpeg')}
    try:
        response = requests.post(SERVER_URL, files=files, timeout=2)
    except Exception as e:
        print("서버 연결 실패. 서버가 켜져 있는지 확인하세요.")

    # 내 화면에 어떻게 찍히고 있는지 보여주기
    cv2.imshow('PC Tester Camera', frame)
    
    # 프레임 조절 (웹캠이면 0.1초 딜레이, 동영상이면 0.05초 정도가 적당)
    time.sleep(0.1) 

    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()