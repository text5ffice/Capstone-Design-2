import firebase_admin
from firebase_admin import credentials, messaging

# 1. 아까 다운받은 서버용 마스터 키 연결
cred = credentials.Certificate("firebase_key.json")
firebase_admin.initialize_app(cred)

# 2. 🎯 타겟 설정: 플러터 앱에서 뜬 아주 긴 토큰 주소를 여기에 붙여넣으세요!
target_token = "e_pMDC1_aUAidRITeBBBKg:APA91bEJax2942-WE4MjNy3XyNl5JVx9f8aui_Bg1iyTIJik2Ac0yK4n7AmOCbHPhh8S6CcnA43vYMC38p9nglq5LOZBiyTt1zGywNUeJht-o76BTtYxn0E"

# 3. 보낼 메시지(알림) 내용 작성
message = messaging.Message(
    notification=messaging.Notification(
        title="⚠️ [경고] 현장 위험 감지!",
        body="최용석 관리자님, A구역 작업자가 안전모를 미착용했습니다.",
    ),
    token=target_token, # 이 주소로 배달해줘!
)

# 4. 알림 발사!
try:
    response = messaging.send(message)
    print("✅ 성공적으로 알림을 보냈습니다. 구글 서버 응답:", response)
except Exception as e:
    print("🚨 알림 전송 실패:", e)