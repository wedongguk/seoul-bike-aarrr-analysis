-- 03_quality_check_queries.sql
-- SQLite 기준 품질 점검 쿼리 모음

-- 1. stg 테이블 행 수
SELECT 'stg_signup_month' AS table_name, COUNT(*) AS row_count FROM stg_signup_month
UNION ALL SELECT 'stg_ride_month', COUNT(*) FROM stg_ride_month
UNION ALL SELECT 'stg_station_snapshot', COUNT(*) FROM stg_station_snapshot
UNION ALL SELECT 'stg_station_usage_month', COUNT(*) FROM stg_station_usage_month;

-- 2. 월별 커버리지
SELECT 'stg_signup_month' AS table_name, MIN(month_ym) AS min_ym, MAX(month_ym) AS max_ym, COUNT(DISTINCT month_ym) AS month_count FROM stg_signup_month
UNION ALL SELECT 'stg_ride_month', MIN(month_ym), MAX(month_ym), COUNT(DISTINCT month_ym) FROM stg_ride_month
UNION ALL SELECT 'stg_station_usage_month', MIN(month_ym), MAX(month_ym), COUNT(DISTINCT month_ym) FROM stg_station_usage_month;

-- 3. 스냅샷별 대여소 수
SELECT snapshot_ym, COUNT(*) AS station_count
FROM stg_station_snapshot
GROUP BY snapshot_ym
ORDER BY snapshot_ym;

-- 4. 성별 표준화 결과
SELECT 'signup' AS dataset, gender, COUNT(*) AS row_count FROM stg_signup_month GROUP BY gender
UNION ALL
SELECT 'ride' AS dataset, gender, COUNT(*) AS row_count FROM stg_ride_month GROUP BY gender;

-- 5. 대여구분 표준화 결과
SELECT pass_group, COUNT(*) AS row_count, SUM(ride_cnt) AS ride_cnt_sum
FROM stg_ride_month
GROUP BY pass_group;

-- 6. 연령대 표준화 결과
SELECT 'signup' AS dataset, age_band, COUNT(*) AS row_count
FROM stg_signup_month
GROUP BY age_band

UNION ALL

SELECT 'ride' AS dataset, age_band, COUNT(*) AS row_count
FROM stg_ride_month
GROUP BY age_band

ORDER BY dataset, age_band;

-- 7. null 점검
SELECT 'stg_signup_month' AS table_name, 'month_ym' AS column_name, SUM(CASE WHEN month_ym IS NULL THEN 1 ELSE 0 END) AS null_count FROM stg_signup_month
UNION ALL SELECT 'stg_signup_month', 'signup_cnt', SUM(CASE WHEN signup_cnt IS NULL THEN 1 ELSE 0 END) FROM stg_signup_month
UNION ALL SELECT 'stg_ride_month', 'station_id', SUM(CASE WHEN station_id IS NULL THEN 1 ELSE 0 END) FROM stg_ride_month
UNION ALL SELECT 'stg_ride_month', 'ride_cnt', SUM(CASE WHEN ride_cnt IS NULL THEN 1 ELSE 0 END) FROM stg_ride_month
UNION ALL SELECT 'stg_station_snapshot', 'station_id', SUM(CASE WHEN station_id IS NULL THEN 1 ELSE 0 END) FROM stg_station_snapshot
UNION ALL SELECT 'stg_station_snapshot', 'rack_cnt', SUM(CASE WHEN rack_cnt IS NULL THEN 1 ELSE 0 END) FROM stg_station_snapshot;

-- 8. 0/음수 점검
SELECT 'stg_signup_month' AS table_name, 'signup_cnt <= 0' AS check_item, COUNT(*) AS issue_count FROM stg_signup_month WHERE signup_cnt <= 0
UNION ALL SELECT 'stg_ride_month', 'ride_cnt <= 0', COUNT(*) FROM stg_ride_month WHERE ride_cnt <= 0
UNION ALL SELECT 'stg_station_snapshot', 'rack_cnt <= 0', COUNT(*) FROM stg_station_snapshot WHERE rack_cnt <= 0
UNION ALL SELECT 'stg_station_usage_month', 'checkout_cnt < 0', COUNT(*) FROM stg_station_usage_month WHERE checkout_cnt < 0
UNION ALL SELECT 'stg_station_usage_month', 'return_cnt < 0', COUNT(*) FROM stg_station_usage_month WHERE return_cnt < 0;

-- 9. 이용정보와 대여소 스냅샷 조인 성공률
WITH ride_station AS (
  SELECT DISTINCT r.month_ym, m.snapshot_ym, r.station_id
  FROM stg_ride_month r
  JOIN stg_month_station_snapshot_map m ON r.month_ym = m.month_ym
  WHERE r.station_id IS NOT NULL AND r.is_ops_excluded = 0
), joined AS (
  SELECT rs.month_ym, rs.snapshot_ym, rs.station_id, s.station_id AS matched_station_id
  FROM ride_station rs
  LEFT JOIN stg_station_snapshot s
    ON rs.snapshot_ym = s.snapshot_ym AND rs.station_id = s.station_id
)
SELECT
  month_ym,
  snapshot_ym,
  COUNT(*) AS ride_station_count,
  SUM(CASE WHEN matched_station_id IS NOT NULL THEN 1 ELSE 0 END) AS matched_station_count,
  ROUND(100.0 * SUM(CASE WHEN matched_station_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS join_success_rate_pct
FROM joined
GROUP BY month_ym, snapshot_ym
ORDER BY month_ym;

-- 10. 대여소별 이용정보 station_id 추출 성공률
SELECT
  month_ym,
  COUNT(*) AS row_count,
  SUM(CASE WHEN station_id IS NOT NULL THEN 1 ELSE 0 END) AS station_id_extracted_count,
  ROUND(100.0 * SUM(CASE WHEN station_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS extract_success_rate_pct
FROM stg_station_usage_month
GROUP BY month_ym
ORDER BY month_ym;
