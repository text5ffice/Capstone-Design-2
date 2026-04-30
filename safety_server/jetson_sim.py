import requests

# 플라스크 서버 주소
url = "http://127.0.0.1:5000/api/alerts"

# 젯슨이 카메라로 인식한 위반 데이터
data = {
    "workerName": "오승민",
    "issue": "추락 (구역 A)",
    "statusColor": "red"
}

# 서버로 데이터 전송!
print("🚀 젯슨: 위반자를 발견하여 서버로 데이터를 전송합니다...")
response = requests.post(url, data=data)
print("✅ 서버 응답:", response.text)