-- 04_create_mart_tables.sql
-- SQLite 기준 mart 테이블 생성 스크립트

DROP TABLE IF EXISTS mart_signup_segment_month;
DROP TABLE IF EXISTS mart_ride_segment_month;
DROP TABLE IF EXISTS mart_growth_month;
DROP TABLE IF EXISTS mart_station_efficiency_month;

CREATE TABLE mart_signup_segment_month AS
SELECT
    month_ym,
    month_date,
    gender,
    age_band,
    SUM(signup_cnt) AS signup_cnt
FROM stg_signup_month
WHERE month_ym BETWEEN 202401 AND 202512
GROUP BY month_ym, month_date, gender, age_band;

CREATE TABLE mart_ride_segment_month AS
SELECT
    month_ym,
    month_date,
    gender,
    age_band,
    pass_group AS ride_type,
    SUM(ride_cnt) AS ride_cnt,
    SUM(distance_m) AS total_distance_m,
    SUM(duration_min) AS total_duration_min,
    CASE WHEN SUM(ride_cnt) > 0 THEN 1.0 * SUM(distance_m) / SUM(ride_cnt) ELSE NULL END AS avg_distance_m_per_ride,
    CASE WHEN SUM(ride_cnt) > 0 THEN 1.0 * SUM(duration_min) / SUM(ride_cnt) ELSE NULL END AS avg_duration_min_per_ride
FROM stg_ride_month
WHERE month_ym BETWEEN 202401 AND 202512
GROUP BY month_ym, month_date, gender, age_band, pass_group;

CREATE TABLE mart_growth_month AS
WITH signup AS (
    SELECT
        month_ym,
        month_date,
        gender,
        age_band,
        SUM(signup_cnt) AS signup_cnt
    FROM stg_signup_month
    WHERE month_ym BETWEEN 202401 AND 202512
    GROUP BY month_ym, month_date, gender, age_band
),
ride AS (
    SELECT
        month_ym,
        month_date,
        gender,
        age_band,
        SUM(CASE WHEN pass_group = 'SUBSCRIPTION' THEN ride_cnt ELSE 0 END) AS sub_ride_cnt,
        SUM(ride_cnt) AS total_ride_cnt
    FROM stg_ride_month
    WHERE month_ym BETWEEN 202310 AND 202512
    GROUP BY month_ym, month_date, gender, age_band
),
keys AS (
    SELECT month_ym, month_date, gender, age_band FROM signup
    UNION
    SELECT month_ym, month_date, gender, age_band FROM ride
),
base AS (
    SELECT
        k.month_ym,
        k.month_date,
        k.gender,
        k.age_band,
        COALESCE(s.signup_cnt, 0) AS signup_cnt,
        COALESCE(r.sub_ride_cnt, 0) AS sub_ride_cnt,
        COALESCE(r.total_ride_cnt, 0) AS total_ride_cnt
    FROM keys k
    LEFT JOIN signup s
        ON k.month_ym = s.month_ym
       AND k.gender = s.gender
       AND k.age_band = s.age_band
    LEFT JOIN ride r
        ON k.month_ym = r.month_ym
       AND k.gender = r.gender
       AND k.age_band = r.age_band
),
with_window AS (
    SELECT
        *,
        LAG(sub_ride_cnt) OVER (
            PARTITION BY gender, age_band
            ORDER BY month_ym
        ) AS prev_sub_ride_cnt,
        AVG(sub_ride_cnt) OVER (
            PARTITION BY gender, age_band
            ORDER BY month_ym
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev_3m_avg_sub_ride_cnt
    FROM base
)
SELECT
    month_ym,
    month_date,
    gender,
    age_band,
    signup_cnt,
    sub_ride_cnt,
    total_ride_cnt,
    CASE WHEN signup_cnt > 0 THEN 1.0 * sub_ride_cnt / signup_cnt ELSE NULL END AS activation_proxy,
    CASE WHEN total_ride_cnt > 0 THEN 1.0 * sub_ride_cnt / total_ride_cnt ELSE NULL END AS subscription_share,
    CASE WHEN prev_sub_ride_cnt > 0 THEN 1.0 * sub_ride_cnt / prev_sub_ride_cnt ELSE NULL END AS retention_proxy_mom,
    CASE WHEN prev_3m_avg_sub_ride_cnt > 0 THEN 1.0 * sub_ride_cnt / prev_3m_avg_sub_ride_cnt ELSE NULL END AS rolling_3m_persistence
FROM with_window
WHERE month_ym BETWEEN 202401 AND 202512;

CREATE TABLE mart_station_efficiency_month AS
WITH ride_station AS (
    SELECT
        month_ym,
        month_date,
        station_id,
        MAX(station_name) AS station_name_from_ride,
        SUM(ride_cnt) AS total_ride_cnt,
        SUM(CASE WHEN pass_group = 'SUBSCRIPTION' THEN ride_cnt ELSE 0 END) AS sub_ride_cnt,
        SUM(CASE WHEN pass_group = 'NON_SUBSCRIPTION' THEN ride_cnt ELSE 0 END) AS non_sub_ride_cnt,
        SUM(distance_m) AS total_distance_m,
        SUM(duration_min) AS total_duration_min
    FROM stg_ride_month
    WHERE month_ym BETWEEN 202401 AND 202512
      AND station_id IS NOT NULL
      AND is_ops_excluded = 0
    GROUP BY month_ym, month_date, station_id
),
joined AS (
    SELECT
        r.month_ym,
        r.month_date,
        m.snapshot_ym,
        r.station_id,
        COALESCE(s.station_name, r.station_name_from_ride) AS station_name,
        s.district,
        s.lat,
        s.lon,
        s.rack_cnt,
        r.total_ride_cnt,
        r.sub_ride_cnt,
        r.non_sub_ride_cnt,
        r.total_distance_m,
        r.total_duration_min
    FROM ride_station r
    LEFT JOIN stg_month_station_snapshot_map m
        ON r.month_ym = m.month_ym
    LEFT JOIN stg_station_snapshot s
        ON m.snapshot_ym = s.snapshot_ym
       AND r.station_id = s.station_id
)
SELECT
    month_ym,
    month_date,
    snapshot_ym,
    station_id,
    station_name,
    district,
    lat,
    lon,
    rack_cnt,
    total_ride_cnt,
    sub_ride_cnt,
    non_sub_ride_cnt,
    CASE WHEN total_ride_cnt > 0 THEN 1.0 * sub_ride_cnt / total_ride_cnt ELSE NULL END AS subscription_share,
    CASE WHEN rack_cnt > 0 THEN 1.0 * total_ride_cnt / rack_cnt ELSE NULL END AS rides_per_rack,
    total_distance_m,
    total_duration_min,
    CASE WHEN total_ride_cnt > 0 THEN 1.0 * total_distance_m / total_ride_cnt ELSE NULL END AS avg_distance_m_per_ride,
    CASE WHEN total_ride_cnt > 0 THEN 1.0 * total_duration_min / total_ride_cnt ELSE NULL END AS avg_duration_min_per_ride,
    CASE WHEN rack_cnt IS NULL THEN 0 ELSE 1 END AS station_snapshot_matched
FROM joined;

CREATE INDEX IF NOT EXISTS idx_mart_signup_segment_month_keys
ON mart_signup_segment_month(month_ym, gender, age_band);

CREATE INDEX IF NOT EXISTS idx_mart_ride_segment_month_keys
ON mart_ride_segment_month(month_ym, gender, age_band, ride_type);

CREATE INDEX IF NOT EXISTS idx_mart_growth_month_keys
ON mart_growth_month(month_ym, gender, age_band);

CREATE INDEX IF NOT EXISTS idx_mart_station_efficiency_month_keys
ON mart_station_efficiency_month(month_ym, station_id);

CREATE INDEX IF NOT EXISTS idx_mart_station_efficiency_district
ON mart_station_efficiency_month(month_ym, district);
