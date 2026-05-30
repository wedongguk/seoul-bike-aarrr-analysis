-- 05_mart_quality_check_queries.sql
-- SQLite 기준 mart 품질 점검 쿼리

SELECT 'mart_signup_segment_month' AS table_name, COUNT(*) AS row_count FROM mart_signup_segment_month
UNION ALL
SELECT 'mart_ride_segment_month', COUNT(*) FROM mart_ride_segment_month
UNION ALL
SELECT 'mart_growth_month', COUNT(*) FROM mart_growth_month
UNION ALL
SELECT 'mart_station_efficiency_month', COUNT(*) FROM mart_station_efficiency_month;

SELECT 'mart_signup_segment_month' AS table_name, MIN(month_ym) AS min_ym, MAX(month_ym) AS max_ym, COUNT(DISTINCT month_ym) AS month_count FROM mart_signup_segment_month
UNION ALL
SELECT 'mart_ride_segment_month', MIN(month_ym), MAX(month_ym), COUNT(DISTINCT month_ym) FROM mart_ride_segment_month
UNION ALL
SELECT 'mart_growth_month', MIN(month_ym), MAX(month_ym), COUNT(DISTINCT month_ym) FROM mart_growth_month
UNION ALL
SELECT 'mart_station_efficiency_month', MIN(month_ym), MAX(month_ym), COUNT(DISTINCT month_ym) FROM mart_station_efficiency_month;

SELECT
    COUNT(*) AS row_count,
    SUM(CASE WHEN signup_cnt < 0 THEN 1 ELSE 0 END) AS negative_signup_cnt,
    SUM(CASE WHEN sub_ride_cnt < 0 THEN 1 ELSE 0 END) AS negative_sub_ride_cnt,
    SUM(CASE WHEN total_ride_cnt < 0 THEN 1 ELSE 0 END) AS negative_total_ride_cnt,
    SUM(CASE WHEN activation_proxy IS NULL THEN 1 ELSE 0 END) AS null_activation_proxy,
    SUM(CASE WHEN subscription_share IS NULL THEN 1 ELSE 0 END) AS null_subscription_share,
    SUM(CASE WHEN subscription_share < 0 OR subscription_share > 1 THEN 1 ELSE 0 END) AS invalid_subscription_share
FROM mart_growth_month;

SELECT
    month_ym,
    COUNT(*) AS station_month_count,
    SUM(station_snapshot_matched) AS matched_count,
    ROUND(100.0 * SUM(station_snapshot_matched) / COUNT(*), 2) AS matched_rate_pct,
    SUM(CASE WHEN rack_cnt IS NULL THEN 1 ELSE 0 END) AS null_rack_cnt_count,
    SUM(CASE WHEN rack_cnt <= 0 THEN 1 ELSE 0 END) AS zero_or_negative_rack_cnt_count
FROM mart_station_efficiency_month
GROUP BY month_ym
ORDER BY month_ym;

SELECT
    month_ym,
    station_id,
    station_name,
    district,
    total_ride_cnt,
    rack_cnt,
    ROUND(rides_per_rack, 2) AS rides_per_rack,
    ROUND(subscription_share, 3) AS subscription_share
FROM mart_station_efficiency_month
WHERE rack_cnt > 0
ORDER BY rides_per_rack DESC
LIMIT 20;
