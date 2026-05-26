-- 02_create_stg_tables.sql
-- SQLite 기준 staging 테이블 생성 스크립트

DROP TABLE IF EXISTS stg_signup_month;
DROP TABLE IF EXISTS stg_ride_month;
DROP TABLE IF EXISTS stg_station_snapshot;
DROP TABLE IF EXISTS stg_station_usage_month;
DROP TABLE IF EXISTS stg_month_station_snapshot_map;

CREATE TABLE stg_signup_month AS
SELECT
  source_file,
  CAST(signup_ym AS INTEGER) AS month_ym,
  substr(CAST(signup_ym AS TEXT),1,4)||'-'||substr(CAST(signup_ym AS TEXT),5,2)||'-01' AS month_date,
  NULLIF(TRIM(member_type_raw),'') AS member_type,
  CASE WHEN age_band_raw IS NULL OR UPPER(TRIM(age_band_raw)) IN ('','NAN','NULL','NONE') THEN 'UNKNOWN'
       ELSE TRIM(age_band_raw) END AS age_band,
  CASE WHEN UPPER(TRIM(gender_raw))='M' THEN 'M'
       WHEN UPPER(TRIM(gender_raw))='F' THEN 'F'
       ELSE 'UNKNOWN' END AS gender,
  CAST(signup_cnt_raw AS INTEGER) AS signup_cnt,
  loaded_at
FROM raw_signup_month;

CREATE TABLE stg_ride_month AS
SELECT
  source_file,
  CAST(ride_ym AS INTEGER) AS month_ym,
  substr(CAST(ride_ym AS TEXT),1,4)||'-'||substr(CAST(ride_ym AS TEXT),5,2)||'-01' AS month_date,
  CAST(station_id_raw AS INTEGER) AS station_id,
  TRIM(station_name_raw) AS station_name_raw,
  CASE WHEN instr(TRIM(station_name_raw),'.')>0
       THEN TRIM(substr(TRIM(station_name_raw), instr(TRIM(station_name_raw),'.')+1))
       ELSE TRIM(station_name_raw) END AS station_name,
  TRIM(pass_type_raw) AS pass_type,
  CASE WHEN TRIM(pass_type_raw)='정기권' THEN 'SUBSCRIPTION'
       ELSE 'NON_SUBSCRIPTION' END AS pass_group,
  CASE WHEN UPPER(TRIM(gender_raw))='M' THEN 'M'
       WHEN UPPER(TRIM(gender_raw))='F' THEN 'F'
       ELSE 'UNKNOWN' END AS gender,
  CASE WHEN age_band_raw IS NULL OR UPPER(TRIM(age_band_raw)) IN ('','NAN','NULL','NONE') THEN 'UNKNOWN'
       ELSE TRIM(age_band_raw) END AS age_band,
  CAST(ride_cnt_raw AS INTEGER) AS ride_cnt,
  CAST(REPLACE(NULLIF(TRIM(exercise_amt_raw),''),',','') AS REAL) AS exercise_amt,
  CAST(REPLACE(NULLIF(TRIM(carbon_amt_raw),''),',','') AS REAL) AS carbon_amt,
  CAST(REPLACE(NULLIF(TRIM(distance_m_raw),''),',','') AS REAL) AS distance_m,
  CAST(REPLACE(NULLIF(TRIM(duration_min_raw),''),',','') AS REAL) AS duration_min,
  CASE WHEN CAST(station_id_raw AS INTEGER)=9980 OR TRIM(station_name_raw) LIKE '%AS센터%' THEN 1 ELSE 0 END AS is_ops_excluded,
  loaded_at
FROM raw_ride_month;

CREATE TABLE stg_station_snapshot AS
WITH base AS (
  SELECT
    snapshot_ym,
    source_file,
    CAST(station_id_raw AS INTEGER) AS station_id,
    TRIM(station_name_raw) AS station_name,
    TRIM(district_raw) AS district,
    TRIM(address_raw) AS address,
    CAST(REPLACE(NULLIF(TRIM(lat_raw),''),',','') AS REAL) AS lat,
    CAST(REPLACE(NULLIF(TRIM(lon_raw),''),',','') AS REAL) AS lon,
    NULLIF(TRIM(installed_at_raw),'') AS installed_at_raw,
    CAST(REPLACE(NULLIF(TRIM(rack_lcd_raw),''),',','') AS INTEGER) AS rack_lcd,
    CAST(REPLACE(NULLIF(TRIM(rack_qr_raw),''),',','') AS INTEGER) AS rack_qr,
    TRIM(operation_type_raw) AS operation_type,
    loaded_at
  FROM raw_station_snapshot
)
SELECT
  snapshot_ym, source_file, station_id, station_name, district, address,
  lat, lon, installed_at_raw, rack_lcd, rack_qr, operation_type,
  CASE
    WHEN operation_type='QR' THEN COALESCE(rack_qr,0)
    WHEN operation_type='LCD' THEN COALESCE(rack_lcd,0)
    WHEN operation_type='LCD,QR' THEN COALESCE(rack_lcd,0)+COALESCE(rack_qr,0)
    ELSE COALESCE(rack_qr,rack_lcd,0)
  END AS rack_cnt,
  loaded_at
FROM base
WHERE station_id IS NOT NULL;

CREATE TABLE stg_station_usage_month AS
SELECT
  source_file,
  CAST(usage_ym AS INTEGER) AS month_ym,
  substr(CAST(usage_ym AS TEXT),1,4)||'-'||substr(CAST(usage_ym AS TEXT),5,2)||'-01' AS month_date,
  TRIM(district_raw) AS district,
  TRIM(station_name_raw) AS station_name_raw,
  CASE WHEN instr(TRIM(station_name_raw),'.')>0
       THEN CAST(substr(TRIM(station_name_raw),1,instr(TRIM(station_name_raw),'.')-1) AS INTEGER)
       ELSE NULL END AS station_id,
  CASE WHEN instr(TRIM(station_name_raw),'.')>0
       THEN TRIM(substr(TRIM(station_name_raw),instr(TRIM(station_name_raw),'.')+1))
       ELSE TRIM(station_name_raw) END AS station_name,
  CAST(checkout_cnt_raw AS INTEGER) AS checkout_cnt,
  CAST(return_cnt_raw AS INTEGER) AS return_cnt,
  loaded_at
FROM raw_station_usage_month;

CREATE TABLE stg_month_station_snapshot_map (
  month_ym INTEGER PRIMARY KEY,
  snapshot_ym INTEGER NOT NULL
);

INSERT INTO stg_month_station_snapshot_map (month_ym, snapshot_ym) VALUES
(202401,202406),(202402,202406),(202403,202406),(202404,202406),(202405,202406),(202406,202406),
(202407,202412),(202408,202412),(202409,202412),(202410,202412),(202411,202412),(202412,202412),
(202501,202506),(202502,202506),(202503,202506),(202504,202506),(202505,202506),(202506,202506),
(202507,202512),(202508,202512),(202509,202512),(202510,202512),(202511,202512),(202512,202512);

CREATE INDEX IF NOT EXISTS idx_stg_signup_month_keys ON stg_signup_month(month_ym, gender, age_band);
CREATE INDEX IF NOT EXISTS idx_stg_ride_month_keys ON stg_ride_month(month_ym, gender, age_band, pass_group);
CREATE INDEX IF NOT EXISTS idx_stg_ride_station ON stg_ride_month(month_ym, station_id);
CREATE INDEX IF NOT EXISTS idx_stg_station_snapshot_keys ON stg_station_snapshot(snapshot_ym, station_id);
CREATE INDEX IF NOT EXISTS idx_stg_station_usage_keys ON stg_station_usage_month(month_ym, station_id);
