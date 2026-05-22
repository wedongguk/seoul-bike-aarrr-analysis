DROP TABLE IF EXISTS raw_signup_month;
DROP TABLE IF EXISTS raw_ride_month;
DROP TABLE IF EXISTS raw_station_snapshot;
DROP TABLE IF EXISTS raw_station_usage_month;

CREATE TABLE raw_signup_month (
    source_file TEXT,
    signup_ym INTEGER,
    member_type_raw TEXT,
    age_band_raw TEXT,
    gender_raw TEXT,
    signup_cnt_raw INTEGER,
    loaded_at TEXT
);

CREATE TABLE raw_ride_month (
    source_file TEXT,
    ride_ym INTEGER,
    station_id_raw TEXT,
    station_name_raw TEXT,
    pass_type_raw TEXT,
    gender_raw TEXT,
    age_band_raw TEXT,
    ride_cnt_raw INTEGER,
    exercise_amt_raw TEXT,
    carbon_amt_raw TEXT,
    distance_m_raw TEXT,
    duration_min_raw TEXT,
    loaded_at TEXT
);

CREATE TABLE raw_station_snapshot (
    snapshot_ym INTEGER,
    source_file TEXT,
    station_id_raw TEXT,
    station_name_raw TEXT,
    district_raw TEXT,
    address_raw TEXT,
    lat_raw TEXT,
    lon_raw TEXT,
    installed_at_raw TEXT,
    rack_lcd_raw TEXT,
    rack_qr_raw TEXT,
    operation_type_raw TEXT,
    loaded_at TEXT
);

CREATE TABLE raw_station_usage_month (
    source_file TEXT,
    usage_ym INTEGER,
    district_raw TEXT,
    station_name_raw TEXT,
    checkout_cnt_raw INTEGER,
    return_cnt_raw INTEGER,
    loaded_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_raw_signup_month_ym ON raw_signup_month(signup_ym);
CREATE INDEX IF NOT EXISTS idx_raw_ride_month_ym ON raw_ride_month(ride_ym);
CREATE INDEX IF NOT EXISTS idx_raw_ride_station ON raw_ride_month(station_id_raw);
CREATE INDEX IF NOT EXISTS idx_raw_station_snapshot_ym ON raw_station_snapshot(snapshot_ym);
CREATE INDEX IF NOT EXISTS idx_raw_station_snapshot_station ON raw_station_snapshot(station_id_raw);
CREATE INDEX IF NOT EXISTS idx_raw_station_usage_month_ym ON raw_station_usage_month(usage_ym);
