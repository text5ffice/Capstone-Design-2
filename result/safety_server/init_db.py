import sqlite3

conn = sqlite3.connect('safety.db')
cursor = conn.cursor()

# 1. 테이블 초기화
cursor.execute('DROP TABLE IF EXISTS violation_logs')
cursor.execute('DROP TABLE IF EXISTS workers')
cursor.execute('DROP TABLE IF EXISTS admin_tokens') # 추가됨

# 2. 작업자 테이블
cursor.execute('''
    CREATE TABLE workers (
        worker_id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        role TEXT NOT NULL
    )
''')

# 3. 위반 로그 테이블
cursor.execute('''
    CREATE TABLE violation_logs (
        log_id INTEGER PRIMARY KEY AUTOINCREMENT,
        worker_id INTEGER,
        issue TEXT NOT NULL,
        time TEXT NOT NULL,
        status_color TEXT NOT NULL,
        image_url TEXT NOT NULL,
        FOREIGN KEY (worker_id) REFERENCES workers (worker_id)
    )
''')

# 4. 관리자 토큰 저장용 테이블 (새로 추가됨!)
cursor.execute('''
    CREATE TABLE admin_tokens (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        token TEXT NOT NULL
    )
''')

# 테스트 데이터 삽입
workers_data = [('최용석', '관리자'), ('김철수', '작업자'), ('이영희', '작업자')]
cursor.executemany('INSERT INTO workers (name, role) VALUES (?, ?)', workers_data)

logs_data = [
    (1, '안전모 미착용', '10:45', 'orange', 'http://127.0.0.1:5000/static/images/test.jpg'),
    (2, '위험구역 접근', '10:30', 'red', 'http://127.0.0.1:5000/static/images/test.jpg')
]
cursor.executemany('''
    INSERT INTO violation_logs (worker_id, issue, time, status_color, image_url)
    VALUES (?, ?, ?, ?, ?)
''', logs_data)

conn.commit()
conn.close()

print("✅ 토큰 테이블이 포함된 최신 DB로 초기화 완료!")