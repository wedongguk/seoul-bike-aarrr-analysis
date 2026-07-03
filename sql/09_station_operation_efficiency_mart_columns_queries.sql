-- 09. 운영 효율 분석 SQL

--------------------------------------------------------------------------------
-- 0) mart 검증
--------------------------------------------------------------------------------
SELECT
    MIN(month_ym) AS min_ym,
    MAX(month_ym) AS max_ym,
    COUNT(*) AS row_count,
    COUNT(DISTINCT month_ym) AS month_count,
    COUNT(DISTINCT station_id) AS station_count,
    SUM(CASE WHEN station_snapshot_matched = 1 THEN 1 ELSE 0 END) AS matched_rows,
    ROUND(100.0 * SUM(CASE WHEN station_snapshot_matched = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS matched_rate_pct,
    SUM(CASE WHEN rack_cnt IS NULL OR rack_cnt <= 0 THEN 1 ELSE 0 END) AS invalid_rack_rows,
    SUM(CASE WHEN total_ride_cnt IS NULL THEN 1 ELSE 0 END) AS null_total_ride_rows
FROM mart_station_efficiency_month;

--------------------------------------------------------------------------------
-- 1) 대여소별 이용건수
--------------------------------------------------------------------------------
WITH base AS (
    SELECT *
    FROM mart_station_efficiency_month
    WHERE station_snapshot_matched = 1
      AND rack_cnt > 0
      AND total_ride_cnt >= 0
),
station_period AS (
    SELECT
        station_id,
        station_name,
        district,
        ROUND(AVG(lat), 6) AS lat,
        ROUND(AVG(lon), 6) AS lon,
        COUNT(DISTINCT month_ym) AS active_month_count,
        SUM(total_ride_cnt) AS total_ride_cnt,
        ROUND(AVG(total_ride_cnt), 2) AS avg_monthly_ride_cnt,
        ROUND(AVG(rack_cnt), 2) AS avg_rack_cnt,
        ROUND(AVG(subscription_share), 4) AS avg_subscription_share
    FROM base
    GROUP BY
        station_id,
        station_name,
        district
)
SELECT
    RANK() OVER (ORDER BY total_ride_cnt DESC) AS ride_rank,
    station_id,
    station_name,
    district,
    lat,
    lon,
    active_month_count,
    CAST(total_ride_cnt AS INTEGER) AS total_ride_cnt,
    avg_monthly_ride_cnt,
    avg_rack_cnt,
    avg_subscription_share
FROM station_period
WHERE lat IS NOT NULL
  AND lon IS NOT NULL
  AND active_month_count = 24
ORDER BY total_ride_cnt DESC
LIMIT 30;

--------------------------------------------------------------------------------
-- 2) 거치대 대비 이용효율
--------------------------------------------------------------------------------
WITH base AS (
    SELECT *
    FROM mart_station_efficiency_month
    WHERE station_snapshot_matched = 1
      AND rack_cnt > 0
      AND total_ride_cnt >= 0
),
station_period AS (
    SELECT
        station_id,
        station_name,
        district,
        ROUND(AVG(lat), 6) AS lat,
        ROUND(AVG(lon), 6) AS lon,
        COUNT(DISTINCT month_ym) AS active_month_count,
        SUM(total_ride_cnt) AS total_ride_cnt,
        ROUND(AVG(total_ride_cnt), 2) AS avg_monthly_ride_cnt,
        ROUND(AVG(rack_cnt), 2) AS avg_rack_cnt,
        ROUND(SUM(total_ride_cnt) / NULLIF(AVG(rack_cnt), 0), 2) AS period_rides_per_rack,
        ROUND(AVG(rides_per_rack), 2) AS avg_monthly_rides_per_rack,
        ROUND(AVG(subscription_share), 4) AS avg_subscription_share
    FROM base
    GROUP BY station_id, station_name, district
)
SELECT
    RANK() OVER (ORDER BY avg_monthly_rides_per_rack DESC) AS efficiency_rank,
    station_id,
    station_name,
    district,
    lat,
    lon,
    active_month_count,
    CAST(total_ride_cnt AS INTEGER) AS total_ride_cnt,
    avg_monthly_ride_cnt,
    avg_rack_cnt,
    period_rides_per_rack,
    avg_monthly_rides_per_rack,
    avg_subscription_share
FROM station_period
WHERE lat IS NOT NULL
  AND lon IS NOT NULL
  AND active_month_count = 24
ORDER BY avg_monthly_rides_per_rack DESC
LIMIT 30;

--------------------------------------------------------------------------------
-- 3) 과수요/저활용 대여소 식별
--------------------------------------------------------------------------------
WITH base AS (
    SELECT *
    FROM mart_station_efficiency_month
    WHERE station_snapshot_matched = 1
      AND rack_cnt > 0
      AND total_ride_cnt >= 0
),
station_period AS (
    SELECT
        station_id,
        station_name,
        district,
        ROUND(AVG(lat), 6) AS lat,
        ROUND(AVG(lon), 6) AS lon,
        COUNT(DISTINCT month_ym) AS active_month_count,
        SUM(total_ride_cnt) AS total_ride_cnt,
        SUM(sub_ride_cnt) AS total_sub_ride_cnt,
        SUM(non_sub_ride_cnt) AS total_non_sub_ride_cnt,
        ROUND(AVG(total_ride_cnt), 2) AS avg_monthly_ride_cnt,
        ROUND(AVG(rack_cnt), 2) AS avg_rack_cnt,
        ROUND(AVG(rides_per_rack), 2) AS avg_monthly_rides_per_rack,
        ROUND(AVG(subscription_share), 4) AS avg_subscription_share
    FROM base
    GROUP BY station_id, station_name, district
),
ranked AS (
    SELECT
        *,
        NTILE(4) OVER (ORDER BY total_ride_cnt) AS demand_quartile,
        NTILE(4) OVER (ORDER BY avg_monthly_rides_per_rack) AS efficiency_quartile,
        NTILE(4) OVER (ORDER BY avg_rack_cnt) AS rack_quartile
    FROM station_period
    WHERE active_month_count = 24
)
SELECT
    station_id,
    station_name,
    district,
    lat,
    lon,
    active_month_count,
    CAST(total_ride_cnt AS INTEGER) AS total_ride_cnt,
    CAST(total_sub_ride_cnt AS INTEGER) AS total_sub_ride_cnt,
    CAST(total_non_sub_ride_cnt AS INTEGER) AS total_non_sub_ride_cnt,
    avg_monthly_ride_cnt,
    avg_rack_cnt,
    avg_monthly_rides_per_rack,
    avg_subscription_share,
    demand_quartile,
    efficiency_quartile,
    rack_quartile,
    CASE
        WHEN demand_quartile = 4 AND efficiency_quartile = 4 THEN '과수요/운영 병목 의심'
        WHEN demand_quartile <= 2 AND efficiency_quartile = 4 THEN '소규모 고효율'
        WHEN demand_quartile = 1 AND efficiency_quartile = 1 THEN '저활용'
        WHEN demand_quartile = 4 AND efficiency_quartile <= 2 THEN '규모는 크지만 거치대 효율 보통'
        ELSE '일반'
    END AS operation_station_type
FROM ranked
ORDER BY
    CASE
        WHEN demand_quartile = 4 AND efficiency_quartile = 4 THEN 1
        WHEN demand_quartile = 1 AND efficiency_quartile = 1 THEN 2
        WHEN demand_quartile <= 2 AND efficiency_quartile = 4 THEN 3
        WHEN demand_quartile = 4 AND efficiency_quartile <= 2 THEN 4
        ELSE 5
    END,
    avg_monthly_rides_per_rack DESC,
    total_ride_cnt DESC;

--------------------------------------------------------------------------------
-- 4) 월별 반복 과수요 후보
--------------------------------------------------------------------------------
WITH base AS (
    SELECT *
    FROM mart_station_efficiency_month
    WHERE station_snapshot_matched = 1
      AND rack_cnt > 0
      AND total_ride_cnt >= 0
),
ranked_month AS (
    SELECT
        month_ym,
        month_date,
        station_id,
        station_name,
        district,
        lat,
        lon,
        rack_cnt,
        total_ride_cnt,
        rides_per_rack,
        subscription_share,
        NTILE(4) OVER (PARTITION BY month_ym ORDER BY total_ride_cnt) AS demand_quartile_in_month,
        NTILE(4) OVER (PARTITION BY month_ym ORDER BY rides_per_rack) AS efficiency_quartile_in_month
    FROM base
),
over_demand_month AS (
    SELECT *
    FROM ranked_month
    WHERE demand_quartile_in_month = 4
      AND efficiency_quartile_in_month = 4
)
SELECT
    station_id,
    station_name,
    district,
    ROUND(AVG(lat), 6) AS lat,
    ROUND(AVG(lon), 6) AS lon,
    COUNT(*) AS over_demand_month_count,
    CAST(SUM(total_ride_cnt) AS INTEGER) AS total_ride_cnt,
    ROUND(AVG(total_ride_cnt), 2) AS avg_monthly_ride_cnt,
    ROUND(AVG(rack_cnt), 2) AS avg_rack_cnt,
    ROUND(AVG(rides_per_rack), 2) AS avg_monthly_rides_per_rack,
    ROUND(AVG(subscription_share), 4) AS avg_subscription_share
FROM over_demand_month
GROUP BY station_id, station_name, district
HAVING over_demand_month_count >= 18
ORDER BY over_demand_month_count DESC, avg_monthly_rides_per_rack DESC, total_ride_cnt DESC;

--------------------------------------------------------------------------------
-- 5) 월별 반복 저활용 후보
--------------------------------------------------------------------------------
WITH base AS (
    SELECT *
    FROM mart_station_efficiency_month
    WHERE station_snapshot_matched = 1
      AND rack_cnt > 0
      AND total_ride_cnt >= 0
),
ranked_month AS (
    SELECT
        month_ym,
        month_date,
        station_id,
        station_name,
        district,
        lat,
        lon,
        rack_cnt,
        total_ride_cnt,
        rides_per_rack,
        subscription_share,
        NTILE(4) OVER (PARTITION BY month_ym ORDER BY total_ride_cnt) AS demand_quartile_in_month,
        NTILE(4) OVER (PARTITION BY month_ym ORDER BY rides_per_rack) AS efficiency_quartile_in_month
    FROM base
),
under_use_month AS (
    SELECT *
    FROM ranked_month
    WHERE demand_quartile_in_month = 1
      AND efficiency_quartile_in_month = 1
)
SELECT
    station_id,
    station_name,
    district,
    ROUND(AVG(lat), 6) AS lat,
    ROUND(AVG(lon), 6) AS lon,
    COUNT(*) AS under_use_month_count,
    CAST(SUM(total_ride_cnt) AS INTEGER) AS total_ride_cnt,
    ROUND(AVG(total_ride_cnt), 2) AS avg_monthly_ride_cnt,
    ROUND(AVG(rack_cnt), 2) AS avg_rack_cnt,
    ROUND(AVG(rides_per_rack), 2) AS avg_monthly_rides_per_rack,
    ROUND(AVG(subscription_share), 4) AS avg_subscription_share
FROM under_use_month
GROUP BY station_id, station_name, district
HAVING under_use_month_count >= 18
ORDER BY under_use_month_count DESC, avg_monthly_rides_per_rack ASC;

--------------------------------------------------------------------------------
-- 6) 10분위 기준 과수요/저활용 대여소 식별
--------------------------------------------------------------------------------
WITH base AS (
    SELECT *
    FROM mart_station_efficiency_month
    WHERE station_snapshot_matched = 1
      AND rack_cnt > 0
      AND total_ride_cnt >= 0
),
station_period AS (
    SELECT
        station_id,
        station_name,
        district,
        ROUND(AVG(lat), 6) AS lat,
        ROUND(AVG(lon), 6) AS lon,
        COUNT(DISTINCT month_ym) AS active_month_count,
        SUM(total_ride_cnt) AS total_ride_cnt,
        SUM(sub_ride_cnt) AS total_sub_ride_cnt,
        SUM(non_sub_ride_cnt) AS total_non_sub_ride_cnt,
        ROUND(AVG(total_ride_cnt), 2) AS avg_monthly_ride_cnt,
        ROUND(AVG(rack_cnt), 2) AS avg_rack_cnt,
        ROUND(AVG(rides_per_rack), 2) AS avg_monthly_rides_per_rack,
        ROUND(AVG(subscription_share), 4) AS avg_subscription_share
    FROM base
    GROUP BY station_id, station_name, district
),
ranked AS (
    SELECT
        *,
        NTILE(10) OVER (ORDER BY total_ride_cnt) AS demand_decile,
        NTILE(10) OVER (ORDER BY avg_monthly_rides_per_rack) AS efficiency_decile,
        NTILE(10) OVER (ORDER BY avg_rack_cnt) AS rack_decile
    FROM station_period
    WHERE active_month_count = 24
)
SELECT
    station_id,
    station_name,
    district,
    lat,
    lon,
    active_month_count,
    CAST(total_ride_cnt AS INTEGER) AS total_ride_cnt,
    CAST(total_sub_ride_cnt AS INTEGER) AS total_sub_ride_cnt,
    CAST(total_non_sub_ride_cnt AS INTEGER) AS total_non_sub_ride_cnt,
    avg_monthly_ride_cnt,
    avg_rack_cnt,
    avg_monthly_rides_per_rack,
    avg_subscription_share,
    demand_decile,
    efficiency_decile,
    rack_decile,
    CASE
        WHEN demand_decile = 10 AND efficiency_decile = 10 THEN '핵심 과수요/운영 병목 후보'
        WHEN demand_decile = 1 AND efficiency_decile = 1 THEN '핵심 저활용 후보'
        WHEN demand_decile <= 5 AND efficiency_decile = 10 THEN '소규모 고효율 후보'
        WHEN demand_decile = 10 AND efficiency_decile <= 5 THEN '대형 수요 안정 처리 후보'
        ELSE '일반'
    END AS operation_station_type
FROM ranked
ORDER BY
    CASE
        WHEN demand_decile = 10 AND efficiency_decile = 10 THEN 1
        WHEN demand_decile = 1 AND efficiency_decile = 1 THEN 2
        WHEN demand_decile <= 5 AND efficiency_decile = 10 THEN 3
        WHEN demand_decile = 10 AND efficiency_decile <= 5 THEN 4
        ELSE 5
    END,
    avg_monthly_rides_per_rack DESC,
    total_ride_cnt DESC;

--------------------------------------------------------------------------------
-- 7) 10분위 기준 월별 반복 과수요 후보
--------------------------------------------------------------------------------
WITH base AS (
    SELECT *
    FROM mart_station_efficiency_month
    WHERE station_snapshot_matched = 1
      AND rack_cnt > 0
      AND total_ride_cnt >= 0
),
ranked_month AS (
    SELECT
        month_ym,
        month_date,
        station_id,
        station_name,
        district,
        lat,
        lon,
        rack_cnt,
        total_ride_cnt,
        rides_per_rack,
        subscription_share,
        NTILE(10) OVER (PARTITION BY month_ym ORDER BY total_ride_cnt) AS demand_decile_in_month,
        NTILE(10) OVER (PARTITION BY month_ym ORDER BY rides_per_rack) AS efficiency_decile_in_month
    FROM base
),
over_demand_month AS (
    SELECT *
    FROM ranked_month
    WHERE demand_decile_in_month = 10
      AND efficiency_decile_in_month = 10
)
SELECT
    station_id,
    station_name,
    district,
    ROUND(AVG(lat), 6) AS lat,
    ROUND(AVG(lon), 6) AS lon,
    COUNT(*) AS over_demand_month_count,
    CAST(SUM(total_ride_cnt) AS INTEGER) AS total_ride_cnt,
    ROUND(AVG(total_ride_cnt), 2) AS avg_monthly_ride_cnt,
    ROUND(AVG(rack_cnt), 2) AS avg_rack_cnt,
    ROUND(AVG(rides_per_rack), 2) AS avg_monthly_rides_per_rack,
    ROUND(AVG(subscription_share), 4) AS avg_subscription_share
FROM over_demand_month
GROUP BY station_id, station_name, district
HAVING over_demand_month_count = 24
ORDER BY over_demand_month_count DESC, avg_monthly_rides_per_rack DESC, total_ride_cnt DESC;

--------------------------------------------------------------------------------
-- 8) 10분위 기준 월별 반복 저활용 후보
--------------------------------------------------------------------------------
WITH base AS (
    SELECT *
    FROM mart_station_efficiency_month
    WHERE station_snapshot_matched = 1
      AND rack_cnt > 0
      AND total_ride_cnt >= 0
),
ranked_month AS (
    SELECT
        month_ym,
        month_date,
        station_id,
        station_name,
        district,
        lat,
        lon,
        rack_cnt,
        total_ride_cnt,
        rides_per_rack,
        subscription_share,
        NTILE(10) OVER (PARTITION BY month_ym ORDER BY total_ride_cnt) AS demand_decile_in_month,
        NTILE(10) OVER (PARTITION BY month_ym ORDER BY rides_per_rack) AS efficiency_decile_in_month
    FROM base
),
under_use_month AS (
    SELECT *
    FROM ranked_month
    WHERE demand_decile_in_month = 1
      AND efficiency_decile_in_month = 1
)
SELECT
    station_id,
    station_name,
    district,
    ROUND(AVG(lat), 6) AS lat,
    ROUND(AVG(lon), 6) AS lon,
    COUNT(*) AS under_use_month_count,
    CAST(SUM(total_ride_cnt) AS INTEGER) AS total_ride_cnt,
    ROUND(AVG(total_ride_cnt), 2) AS avg_monthly_ride_cnt,
    ROUND(AVG(rack_cnt), 2) AS avg_rack_cnt,
    ROUND(AVG(rides_per_rack), 2) AS avg_monthly_rides_per_rack,
    ROUND(AVG(subscription_share), 4) AS avg_subscription_share
FROM under_use_month
GROUP BY station_id, station_name, district
HAVING under_use_month_count = 24
ORDER BY under_use_month_count DESC, avg_monthly_rides_per_rack ASC;

--------------------------------------------------------------------------------
-- 9) 자치구별 운영 효율 요약
--------------------------------------------------------------------------------
WITH base AS (
    SELECT *
    FROM mart_station_efficiency_month
    WHERE station_snapshot_matched = 1
      AND rack_cnt > 0
      AND total_ride_cnt >= 0
),
station_period AS (
    SELECT
        station_id,
        station_name,
        district,
        COUNT(DISTINCT month_ym) AS active_month_count,
        SUM(total_ride_cnt) AS total_ride_cnt,
        AVG(total_ride_cnt) AS avg_monthly_ride_cnt,
        AVG(rack_cnt) AS avg_rack_cnt,
        AVG(rides_per_rack) AS avg_monthly_rides_per_rack
    FROM base
    GROUP BY station_id, station_name, district
),
ranked AS (
    SELECT
        *,
        NTILE(10) OVER (ORDER BY total_ride_cnt) AS demand_decile,
        NTILE(10) OVER (ORDER BY avg_monthly_rides_per_rack) AS efficiency_decile
    FROM station_period
    WHERE active_month_count = 24
)
SELECT
    district,
    COUNT(*) AS station_count,
    CAST(SUM(total_ride_cnt) AS INTEGER) AS total_ride_cnt,
    ROUND(AVG(avg_monthly_ride_cnt), 2) AS avg_monthly_ride_cnt_per_station,
    ROUND(AVG(avg_rack_cnt), 2) AS avg_rack_cnt,
    ROUND(AVG(avg_monthly_rides_per_rack), 2) AS avg_monthly_rides_per_rack,
    SUM(CASE WHEN demand_decile = 10 AND efficiency_decile = 10 THEN 1 ELSE 0 END) AS over_demand_station_count,
    SUM(CASE WHEN demand_decile = 1 AND efficiency_decile = 1 THEN 1 ELSE 0 END) AS under_use_station_count
FROM ranked
GROUP BY district
ORDER BY avg_monthly_rides_per_rack DESC;
