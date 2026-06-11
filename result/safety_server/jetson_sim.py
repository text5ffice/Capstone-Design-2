import requests
import time

# 🚨 플라스크 서버 주소 (앱, 서버와 동일하게 용석님 맥북 IP로 통일!)
url = "http://192.168.1.108:5000/api/alerts"

# 젯슨이 카메라로 인식한 가짜 위반 데이터
data = {
    "workerName": "최용석",
    "issue": "안전모 미착용 (구역 A)",  # 원하는 위반 내용으로 자유롭게 바꿔보세요!
    "statusColor": "red"
}

print(f"🚀 젯슨 시뮬레이터: [{data['workerName']}] 작업자의 데이터를 서버로 전송합니다...")

try:
    # 서버로 데이터 전송! (새로운 시스템에 맞춰 POST 요청)
    response = requests.post(url, data=data)
    
    if response.status_code == 201:
        print("✅ 전송 성공! 태블릿(앱)에 알림이 울렸는지 확인해보세요.")
        print("📥 서버 응답:", response.json())
    else:
        print("🚨 서버에서 에러를 반환했습니다. 상태 코드:", response.status_code)
        print("응답 내용:", response.text)

except requests.exceptions.ConnectionError:
    print("🚨 서버 연결 실패! 터미널에서 'python3 app.py'가 켜져 있는지, IP 주소가 맞는지 확인해주세요.")