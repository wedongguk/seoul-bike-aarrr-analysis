-- 06_acquisition_analysis.sql
-- Acquisition 분석: age_band='기타' 포함/제외 비교
-- 사용 테이블: mart_signup_segment_month

-- 0. age_band='기타' 전체 비중
SELECT
    SUM(signup_cnt) AS total_signup_cnt,
    SUM(CASE WHEN age_band = '기타' THEN signup_cnt ELSE 0 END) AS other_signup_cnt,
    SUM(CASE WHEN age_band <> '기타' THEN signup_cnt ELSE 0 END) AS valid_age_signup_cnt,
    ROUND(1.0 * SUM(CASE WHEN age_band = '기타' THEN signup_cnt ELSE 0 END) / SUM(signup_cnt), 4) AS other_age_share
FROM mart_signup_segment_month;

-- 1. 월별 age_band='기타' 영향
SELECT
    month_ym,
    month_date,
    SUM(signup_cnt) AS signup_cnt_include_other,
    SUM(CASE WHEN age_band <> '기타' THEN signup_cnt ELSE 0 END) AS signup_cnt_exclude_other,
    SUM(CASE WHEN age_band = '기타' THEN signup_cnt ELSE 0 END) AS other_signup_cnt,
    ROUND(CASE WHEN SUM(signup_cnt) > 0 THEN 1.0 * SUM(CASE WHEN age_band = '기타' THEN signup_cnt ELSE 0 END) / SUM(signup_cnt) ELSE NULL END, 4) AS other_age_share
FROM mart_signup_segment_month
GROUP BY month_ym, month_date
ORDER BY month_ym;

-- Q1. 성별·연령대별 신규가입 규모: 기타 포함/제외 비교
WITH scoped AS (
    SELECT 'include_other' AS scope, month_ym, gender, age_band, signup_cnt
    FROM mart_signup_segment_month
    WHERE LOWER(TRIM(COALESCE(gender, ''))) <> 'unknown'
      AND LOWER(TRIM(COALESCE(age_band, ''))) <> 'unknown'
    UNION ALL
    SELECT 'exclude_other' AS scope, month_ym, gender, age_band, signup_cnt
    FROM mart_signup_segment_month
    WHERE age_band <> '기타'
      AND LOWER(TRIM(COALESCE(gender, ''))) <> 'unknown'
      AND LOWER(TRIM(COALESCE(age_band, ''))) <> 'unknown'
),
segment AS (
    SELECT scope, gender, age_band, SUM(signup_cnt) AS signup_cnt, ROUND(AVG(signup_cnt), 2) AS avg_monthly_signup_cnt, COUNT(DISTINCT month_ym) AS active_month_count
    FROM scoped
    GROUP BY scope, gender, age_band
),
scope_total AS (
    SELECT scope, SUM(signup_cnt) AS total_signup_cnt
    FROM segment
    GROUP BY scope
),
ranked AS (
    SELECT s.scope, RANK() OVER (PARTITION BY s.scope ORDER BY s.signup_cnt DESC) AS signup_rank, s.gender, s.age_band, s.signup_cnt, ROUND(1.0 * s.signup_cnt / t.total_signup_cnt, 4) AS signup_share, s.avg_monthly_signup_cnt, s.active_month_count
    FROM segment s JOIN scope_total t ON s.scope = t.scope
)
SELECT * FROM ranked ORDER BY scope, signup_rank;

-- Q2-A. 월별 신규가입 추이 + 전월 대비 변화
WITH duration AS(
    SELECT *
    FROM mart_signup_segment_month
    UNION ALL
    SELECT month_ym, month_date, gender, age_band, SUM(signup_cnt) AS signup_cnt
    FROM stg_signup_month
    WHERE month_ym = 202312
    GROUP BY month_ym, month_date, gender, age_band
),
monthly AS (
    SELECT month_ym, month_date, SUM(signup_cnt) AS signup_cnt
    FROM duration
    WHERE LOWER(TRIM(COALESCE(gender, ''))) <> 'unknown'
      AND LOWER(TRIM(COALESCE(age_band, ''))) <> 'unknown'
    GROUP BY month_ym, month_date
),
with_mom AS (
    SELECT *, LAG(signup_cnt) OVER (ORDER BY month_ym) AS prev_month_signup_cnt
    FROM monthly
)
SELECT month_ym, month_date, signup_cnt, signup_cnt - prev_month_signup_cnt AS mom_signup_diff,
       ROUND(CASE WHEN prev_month_signup_cnt > 0 THEN 1.0 * (signup_cnt - prev_month_signup_cnt) / prev_month_signup_cnt ELSE NULL END, 4) AS mom_signup_growth_rate
FROM with_mom
WHERE month_ym BETWEEN 202401 AND 202512
ORDER BY month_ym;

-- Q2-B. 전년동월 대비 변화
WITH monthly AS (
    SELECT month_ym, month_date, SUM(signup_cnt) AS signup_cnt
    FROM mart_signup_segment_month
    WHERE LOWER(TRIM(COALESCE(gender, ''))) <> 'unknown'
      AND LOWER(TRIM(COALESCE(age_band, ''))) <> 'unknown'
    GROUP BY month_ym, month_date
)
SELECT cur.month_ym, cur.month_date, cur.signup_cnt AS signup_cnt, prev.signup_cnt AS prev_year_same_month_signup_cnt,
       cur.signup_cnt - prev.signup_cnt AS yoy_signup_diff,
       ROUND(CASE WHEN prev.signup_cnt > 0 THEN 1.0 * (cur.signup_cnt - prev.signup_cnt) / prev.signup_cnt ELSE NULL END, 4) AS yoy_signup_growth_rate
FROM monthly cur
JOIN monthly prev ON cur.month_ym = prev.month_ym + 100
ORDER BY cur.month_ym;

-- Q2-C. 계절성 확인
WITH monthly AS (
    SELECT month_ym,
           CAST(SUBSTR(CAST(month_ym AS TEXT), 1, 4) AS INTEGER) AS year_no,
           CAST(SUBSTR(CAST(month_ym AS TEXT), 5, 2) AS INTEGER) AS month_no,
           SUM(signup_cnt) AS signup_cnt
    FROM mart_signup_segment_month
    WHERE LOWER(TRIM(COALESCE(gender, ''))) <> 'unknown'
      AND LOWER(TRIM(COALESCE(age_band, ''))) <> 'unknown'
    GROUP BY month_ym
)
SELECT month_no,
       SUM(CASE WHEN year_no = 2024 THEN signup_cnt ELSE 0 END) AS signup_cnt_2024,
       SUM(CASE WHEN year_no = 2025 THEN signup_cnt ELSE 0 END) AS signup_cnt_2025,
       ROUND(AVG(signup_cnt), 2) AS avg_signup_cnt,
       COUNT(*) AS year_count
FROM monthly
GROUP BY month_no
ORDER BY month_no;

-- Q3. 성별·연령대별 전년동월 대비 성장 기여
WITH scoped AS (
    SELECT 'include_other' AS scope, month_ym, gender, age_band, signup_cnt
    FROM mart_signup_segment_month
    WHERE LOWER(TRIM(COALESCE(gender, ''))) <> 'unknown'
      AND LOWER(TRIM(COALESCE(age_band, ''))) <> 'unknown'
    UNION ALL
    SELECT 'exclude_other' AS scope, month_ym, gender, age_band, signup_cnt
    FROM mart_signup_segment_month
    WHERE age_band <> '기타'
      AND LOWER(TRIM(COALESCE(gender, ''))) <> 'unknown'
      AND LOWER(TRIM(COALESCE(age_band, ''))) <> 'unknown'
),
monthly_segment AS (
    SELECT scope, month_ym,
           CAST(SUBSTR(CAST(month_ym AS TEXT), 1, 4) AS INTEGER) AS year_no,
           CAST(SUBSTR(CAST(month_ym AS TEXT), 5, 2) AS INTEGER) AS month_no,
           gender, age_band, SUM(signup_cnt) AS signup_cnt
    FROM scoped
    GROUP BY scope, month_ym, gender, age_band
),
yoy_segment AS (
    SELECT cur.scope, cur.gender, cur.age_band, cur.month_no, cur.signup_cnt AS signup_cnt_2025, prev.signup_cnt AS signup_cnt_2024, cur.signup_cnt - prev.signup_cnt AS yoy_signup_diff
    FROM monthly_segment cur
    JOIN monthly_segment prev
      ON cur.scope = prev.scope AND cur.gender = prev.gender AND cur.age_band = prev.age_band AND cur.month_no = prev.month_no
     AND cur.year_no = 2025 AND prev.year_no = 2024
),
segment_growth AS (
    SELECT scope, gender, age_band, SUM(signup_cnt_2024) AS signup_cnt_2024, SUM(signup_cnt_2025) AS signup_cnt_2025, SUM(yoy_signup_diff) AS yoy_signup_diff
    FROM yoy_segment
    GROUP BY scope, gender, age_band
),
total_growth AS (
    SELECT scope, SUM(yoy_signup_diff) AS total_yoy_signup_diff
    FROM segment_growth
    GROUP BY scope
)
SELECT sg.scope, RANK() OVER (PARTITION BY sg.scope ORDER BY sg.yoy_signup_diff DESC) AS growth_rank, sg.gender, sg.age_band, sg.signup_cnt_2024, sg.signup_cnt_2025, sg.yoy_signup_diff,
       ROUND(CASE WHEN sg.signup_cnt_2024 > 0 THEN 1.0 * sg.yoy_signup_diff / sg.signup_cnt_2024 ELSE NULL END, 4) AS yoy_signup_growth_rate,
       ROUND(CASE WHEN tg.total_yoy_signup_diff != 0 THEN 1.0 * sg.yoy_signup_diff / tg.total_yoy_signup_diff ELSE NULL END, 4) AS growth_contribution_share
FROM segment_growth sg
JOIN total_growth tg ON sg.scope = tg.scope
ORDER BY sg.scope, growth_rank;

WITH scoped AS (
    SELECT 'include_other' AS scope, month_ym, gender, age_band, signup_cnt
    FROM mart_signup_segment_month
    WHERE LOWER(TRIM(COALESCE(gender, ''))) <> 'unknown'
      AND LOWER(TRIM(COALESCE(age_band, ''))) <> 'unknown'
    UNION ALL
    SELECT 'exclude_other' AS scope, month_ym, gender, age_band, signup_cnt
    FROM mart_signup_segment_month
    WHERE age_band <> '기타'
      AND LOWER(TRIM(COALESCE(gender, ''))) <> 'unknown'
      AND LOWER(TRIM(COALESCE(age_band, ''))) <> 'unknown'
),
monthly_segment AS (
    SELECT scope, month_ym,
           CAST(SUBSTR(CAST(month_ym AS TEXT), 1, 4) AS INTEGER) AS year_no,
           CAST(SUBSTR(CAST(month_ym AS TEXT), 5, 2) AS INTEGER) AS month_no,
           gender, age_band, SUM(signup_cnt) AS signup_cnt
    FROM scoped
    GROUP BY scope, month_ym, gender, age_band
),
yoy_segment AS (
    SELECT cur.scope, cur.gender, cur.age_band, cur.month_no, cur.signup_cnt AS signup_cnt_2025, prev.signup_cnt AS signup_cnt_2024, cur.signup_cnt - prev.signup_cnt AS yoy_signup_diff
    FROM monthly_segment cur
    JOIN monthly_segment prev
      ON cur.scope = prev.scope AND cur.gender = prev.gender AND cur.age_band = prev.age_band AND cur.month_no = prev.month_no
     AND cur.year_no = 2025 AND prev.year_no = 2024
),
segment_growth AS (
    SELECT scope, gender, age_band, SUM(signup_cnt_2024) AS signup_cnt_2024, SUM(signup_cnt_2025) AS signup_cnt_2025, SUM(yoy_signup_diff) AS yoy_signup_diff
    FROM yoy_segment
    GROUP BY scope, gender, age_band
),
total_growth AS (
    SELECT scope, SUM(yoy_signup_diff) AS total_yoy_signup_diff
    FROM segment_growth
    GROUP BY scope
),
with_metrics AS(
	SELECT sg.scope, sg.gender, sg.age_band, sg.signup_cnt_2024, sg.signup_cnt_2025, sg.yoy_signup_diff,
	       ROUND(CASE WHEN sg.signup_cnt_2024 > 0 THEN 1.0 * sg.yoy_signup_diff / sg.signup_cnt_2024 ELSE NULL END, 4) AS yoy_signup_growth_rate,
           ROUND(CASE WHEN tg.total_yoy_signup_diff != 0 THEN 1.0 * sg.yoy_signup_diff / tg.total_yoy_signup_diff ELSE NULL END, 4) AS growth_contribution_share
	FROM segment_growth sg
	JOIN total_growth tg ON sg.scope = tg.scope
)
SELECT
    scope,
    RANK() OVER (PARTITION BY scope ORDER BY yoy_signup_growth_rate DESC) AS rate_rank,
    gender, age_band, signup_cnt_2024, signup_cnt_2025,
    yoy_signup_diff,
    yoy_signup_growth_rate,
    growth_contribution_share
FROM with_metrics
ORDER BY scope, rate_rank;

--월별 성장 주도 세그먼트 TOP3
WITH monthly_segment AS (
    SELECT month_ym,
           CAST(SUBSTR(CAST(month_ym AS TEXT), 1, 4) AS INTEGER) AS year_no,
           CAST(SUBSTR(CAST(month_ym AS TEXT), 5, 2) AS INTEGER) AS month_no,
           gender, age_band, SUM(signup_cnt) AS signup_cnt
    FROM mart_signup_segment_month
    WHERE age_band <> '기타'
      AND LOWER(TRIM(COALESCE(gender, ''))) <> 'unknown'
      AND LOWER(TRIM(COALESCE(age_band, ''))) <> 'unknown'
    GROUP BY month_ym, gender, age_band
),
yoy_segment AS (
    SELECT cur.month_ym, cur.gender, cur.age_band, cur.signup_cnt AS signup_cnt_2025, prev.signup_cnt AS signup_cnt_2024, cur.signup_cnt - prev.signup_cnt AS yoy_signup_diff
    FROM monthly_segment cur
    JOIN monthly_segment prev
      ON cur.gender = prev.gender AND cur.age_band = prev.age_band AND cur.month_no = prev.month_no
     AND cur.year_no = 2025 AND prev.year_no = 2024
),
ranked AS (
    SELECT *, RANK() OVER (PARTITION BY month_ym ORDER BY yoy_signup_diff DESC) AS growth_rank_in_month
    FROM yoy_segment
)
SELECT month_ym, growth_rank_in_month, gender, age_band, signup_cnt_2024, signup_cnt_2025, yoy_signup_diff
FROM ranked
WHERE growth_rank_in_month <= 3
ORDER BY month_ym, growth_rank_in_month;

WITH monthly_segment AS (
    SELECT
        month_ym,
        CAST(SUBSTR(CAST(month_ym AS TEXT), 1, 4) AS INTEGER) AS year_no,
        CAST(SUBSTR(CAST(month_ym AS TEXT), 5, 2) AS INTEGER) AS month_no,
        gender,
        age_band,
        SUM(signup_cnt) AS signup_cnt
    FROM mart_signup_segment_month
    WHERE age_band <> '기타'
      AND LOWER(TRIM(COALESCE(gender, ''))) <> 'unknown'
      AND LOWER(TRIM(COALESCE(age_band, ''))) <> 'unknown'
    GROUP BY
        month_ym,
        gender,
        age_band
),
yoy_segment AS (
    SELECT
        cur.month_ym,
        cur.gender,
        cur.age_band,
        prev.signup_cnt AS signup_cnt_2024,
        cur.signup_cnt AS signup_cnt_2025,
        cur.signup_cnt - prev.signup_cnt AS yoy_signup_diff,
        CASE
            WHEN prev.signup_cnt > 0
            THEN 1.0 * (cur.signup_cnt - prev.signup_cnt) / prev.signup_cnt
            ELSE NULL
        END AS yoy_signup_growth_rate
    FROM monthly_segment cur
    JOIN monthly_segment prev
      ON cur.gender = prev.gender
     AND cur.age_band = prev.age_band
     AND cur.month_no = prev.month_no
     AND cur.year_no = 2025
     AND prev.year_no = 2024
),
ranked AS (
    SELECT
        *,
        RANK() OVER (
            PARTITION BY month_ym
            ORDER BY yoy_signup_growth_rate DESC
        ) AS rate_rank_in_month
    FROM yoy_segment
)
SELECT
    month_ym,
    rate_rank_in_month,
    gender,
    age_band,
    signup_cnt_2024,
    signup_cnt_2025,
    yoy_signup_diff,
    ROUND(yoy_signup_growth_rate, 4) AS yoy_signup_growth_rate
FROM ranked
WHERE rate_rank_in_month <= 3
ORDER BY
    month_ym,
    rate_rank_in_month;
