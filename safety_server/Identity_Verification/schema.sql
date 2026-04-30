-- ===== NFC 신원확인 시스템 데이터베이스 =====
-- 
-- [실행 방법]
--   1. MySQL 접속: mysql -u root -p
--   2. 이 파일 실행: source schema.sql
--   또는 MySQL Workbench에서 열어서 실행

-- 데이터베이스 생성
CREATE DATABASE IF NOT EXISTS safety_db DEFAULT CHARACTER SET utf8mb4;
USE safety_db;


-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- 1. 작업자 테이블 (NFC 카드가 등록된 사람들)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CREATE TABLE IF NOT EXISTS workers (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(50)  NOT NULL COMMENT '작업자 이름',
    company     VARCHAR(100) DEFAULT '' COMMENT '소속 회사',
    role        VARCHAR(50)  DEFAULT '' COMMENT '직종 (철근공, 목공, 전기공 등)',
    phone       VARCHAR(20)  DEFAULT '' COMMENT '연락처',
    nfc_uid     VARCHAR(30)  NOT NULL UNIQUE COMMENT 'NFC 카드 UID (예: A3:B2:C1:D4)',
    is_active   BOOLEAN      DEFAULT TRUE COMMENT '활성 상태 (퇴사하면 FALSE)',
    created_at  DATETIME     DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_nfc_uid (nfc_uid)  -- UID로 빠르게 검색하기 위한 인덱스
) COMMENT='등록된 작업자 목록';


-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- 2. 출입 기록 테이블 (성공/실패 모두 기록)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CREATE TABLE IF NOT EXISTS access_logs (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    worker_id   INT          NULL COMMENT '작업자 ID (미등록이면 NULL)',
    gate_id     VARCHAR(30)  NOT NULL COMMENT '출입구 이름 (GATE_A, GATE_B 등)',
    nfc_uid_raw VARCHAR(30)  DEFAULT '' COMMENT '실패 시 원본 UID 저장',
    status      ENUM('SUCCESS', 'FAIL') NOT NULL COMMENT '인증 결과',
    created_at  DATETIME     DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_created_at (created_at),   -- 날짜별 조회 빠르게
    INDEX idx_worker_id (worker_id),     -- 작업자별 조회 빠르게
    
    FOREIGN KEY (worker_id) REFERENCES workers(id) ON DELETE SET NULL
) COMMENT='NFC 출입 기록';


-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- 3. 관리자 디바이스 테이블 (푸시 알림용)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CREATE TABLE IF NOT EXISTS admin_devices (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    admin_name  VARCHAR(50)  NOT NULL COMMENT '관리자 이름',
    fcm_token   TEXT         NOT NULL COMMENT 'Firebase 푸시 토큰',
    is_active   BOOLEAN      DEFAULT TRUE,
    created_at  DATETIME     DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) COMMENT='관리자 앱 푸시 알림 토큰';


-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- 테스트 데이터 (개발할 때 쓸 샘플)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
INSERT INTO workers (name, company, role, phone, nfc_uid) VALUES
('김철수', '한빛건설', '철근공',  '010-1111-2222', 'A3:B2:C1:D4'),
('이영희', '한빛건설', '목공',    '010-3333-4444', 'F1:E2:D3:C4'),
('박민수', '대한전기', '전기공',  '010-5555-6666', '11:22:33:44'),
('정수진', '안전관리', '안전관리자','010-7777-8888', 'AA:BB:CC:DD'),
('최동현', '한빛건설', '배관공',  '010-9999-0000', '55:66:77:88');

-- 확인
SELECT '✅ 데이터베이스 생성 완료!' AS result;
SELECT CONCAT('등록된 작업자: ', COUNT(*), '명') AS info FROM workers;
