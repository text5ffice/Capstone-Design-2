import sqlite3
import os
import glob

print("🧹 데이터 초기화를 시작합니다...")

# 1. DB 기록 완전 삭제 (테이블 구조는 남기고 알맹이만 삭제)
try:
    conn = sqlite3.connect('safety.db')
    cursor = conn.cursor()
    
    # 위반 기록과 작업자 목록을 깨끗하게 비웁니다.
    cursor.execute('DELETE FROM violation_logs')
    cursor.execute('DELETE FROM workers')
    
    # 혹시 모를 찌꺼기를 위해 번호표(Auto Increment)도 초기화
    cursor.execute('DELETE FROM sqlite_sequence WHERE name="violation_logs"')
    cursor.execute('DELETE FROM sqlite_sequence WHERE name="workers"')
    
    conn.commit()
    conn.close()
    print("✅ 데이터베이스(safety.db) 기록 삭제 완료!")
except Exception as e:
    print(f"🚨 DB 삭제 중 에러 발생: {e}")

# 2. 캡처된 사진 파일들 삭제
try:
    # static/images 폴더 안의 모든 jpg 파일을 찾습니다.
    files = glob.glob('static/images/*.jpg')
    deleted_count = 0
    
    for f in files:
        # 안전모 미착용 기본 이미지인 'test.jpg'는 지우지 않고 남겨둡니다.
        if "test.jpg" not in f:
            os.remove(f)
            deleted_count += 1
            
    print(f"✅ 캡처된 사진 {deleted_count}장 삭제 완료!")
except Exception as e:
    print(f"🚨 사진 삭제 중 에러 발생: {e}")

print("✨ 모든 초기화가 끝났습니다! 앱을 새로고침 해보세요.")