-- 07_activation_analysis_queries.sql
-- Activation 분석 SQL
-- 사용 테이블: mart_growth_month

-- 1. 월별 Activation 흐름: 기타 포함, unknown 제외
WITH monthly AS (
    SELECT
        month_ym,
        month_date,
        SUM(signup_cnt) AS signup_cnt,
        SUM(sub_ride_cnt) AS sub_ride_cnt,
        SUM(total_ride_cnt) AS total_ride_cnt
    FROM mart_growth_month
    WHERE LOWER(TRIM(COALESCE(gender, ''))) <> 'unknown'
      AND LOWER(TRIM(COALESCE(age_band, ''))) <> 'unknown'
    GROUP BY month_ym, month_date
)
SELECT
    month_ym,
    month_date,
    signup_cnt,
    sub_ride_cnt,
    total_ride_cnt,
    ROUND(CASE WHEN signup_cnt > 0 THEN 1.0 * sub_ride_cnt / signup_cnt ELSE NULL END, 4) AS sub_rides_per_signup,
    ROUND(CASE WHEN total_ride_cnt > 0 THEN 1.0 * sub_ride_cnt / total_ride_cnt ELSE NULL END, 4) AS same_month_subscription_share
FROM monthly
ORDER BY month_ym;

-- 2. 세그먼트별 Activation 강도: 기타 제외, unknown 제외
WITH segment AS (
    SELECT
        gender,
        age_band,
        SUM(signup_cnt) AS signup_cnt,
        SUM(sub_ride_cnt) AS sub_ride_cnt,
        SUM(total_ride_cnt) AS total_ride_cnt
    FROM mart_growth_month
    WHERE age_band <> '기타'
      AND LOWER(TRIM(COALESCE(gender, ''))) <> 'unknown'
      AND LOWER(TRIM(COALESCE(age_band, ''))) <> 'unknown'
    GROUP BY gender, age_band
),
total AS (
    SELECT
        SUM(signup_cnt) AS total_signup_cnt,
        SUM(sub_ride_cnt) AS total_sub_ride_cnt
    FROM segment
)
SELECT
    RANK() OVER (ORDER BY 1.0 * s.sub_ride_cnt / NULLIF(s.signup_cnt, 0) DESC) AS activation_rank,
    s.gender,
    s.age_band,
    s.signup_cnt,
    s.sub_ride_cnt,
    s.total_ride_cnt,
    ROUND(CASE WHEN s.signup_cnt > 0 THEN 1.0 * s.sub_ride_cnt / s.signup_cnt ELSE NULL END, 4) AS sub_rides_per_signup,
    ROUND(CASE WHEN s.total_ride_cnt > 0 THEN 1.0 * s.sub_ride_cnt / s.total_ride_cnt ELSE NULL END, 4) AS same_month_subscription_share,
    ROUND(1.0 * s.signup_cnt / t.total_signup_cnt, 4) AS signup_share,
    ROUND(1.0 * s.sub_ride_cnt / t.total_sub_ride_cnt, 4) AS sub_ride_share,
    ROUND(1.0 * s.sub_ride_cnt / t.total_sub_ride_cnt - 1.0 * s.signup_cnt / t.total_signup_cnt, 4) AS sub_vs_signup_share_gap
FROM segment s
CROSS JOIN total t
ORDER BY sub_rides_per_signup DESC;

-- 3. 세그먼트 유형 분류
WITH segment AS (
    SELECT
        gender,
        age_band,
        SUM(signup_cnt) AS signup_cnt,
        SUM(sub_ride_cnt) AS sub_ride_cnt,
        SUM(total_ride_cnt) AS total_ride_cnt,
        CASE WHEN SUM(signup_cnt) > 0 THEN 1.0 * SUM(sub_ride_cnt) / SUM(signup_cnt) ELSE NULL END AS sub_rides_per_signup,
        CASE WHEN SUM(total_ride_cnt) > 0 THEN 1.0 * SUM(sub_ride_cnt) / SUM(total_ride_cnt) ELSE NULL END AS same_month_subscription_share
    FROM mart_growth_month
    WHERE age_band <> '기타'
      AND LOWER(TRIM(COALESCE(gender, ''))) <> 'unknown'
      AND LOWER(TRIM(COALESCE(age_band, ''))) <> 'unknown'
    GROUP BY gender, age_band
),
ranked AS (
    SELECT
        *,
        NTILE(4) OVER (ORDER BY signup_cnt) AS signup_quartile,
        NTILE(4) OVER (ORDER BY sub_rides_per_signup) AS activation_quartile,
        NTILE(4) OVER (ORDER BY same_month_subscription_share) AS subscription_share_quartile
    FROM segment
    WHERE sub_rides_per_signup IS NOT NULL
)
SELECT
    gender,
    age_band,
    signup_cnt,
    sub_ride_cnt,
    total_ride_cnt,
    ROUND(sub_rides_per_signup, 4) AS sub_rides_per_signup,
    ROUND(same_month_subscription_share, 4) AS same_month_subscription_share,
    signup_quartile,
    activation_quartile,
    subscription_share_quartile,
    CASE
        WHEN signup_quartile = 4 AND activation_quartile = 4 AND subscription_share_quartile = 4 THEN '가입 규모 큼 + 정기권 이용 강함'
        WHEN signup_quartile = 4 AND activation_quartile <= 2 THEN '가입은 많지만 정기권 이용 약함'
        WHEN signup_quartile <= 2 AND activation_quartile = 4 THEN '가입 규모는 작지만 이용 강도 높음'
        WHEN activation_quartile = 4 AND subscription_share_quartile = 4 THEN '정기권 중심 이용 강함'
        ELSE '일반'
    END AS activation_segment_type
FROM ranked
ORDER BY
    CASE
        WHEN signup_quartile = 4 AND activation_quartile = 4 AND subscription_share_quartile = 4 THEN 1
        WHEN signup_quartile = 4 AND activation_quartile <= 2 THEN 2
        WHEN signup_quartile <= 2 AND activation_quartile = 4 THEN 3
        ELSE 4
    END,
    signup_cnt DESC;

-- 4. 월별 가입은 많지만 정기권 이용이 약한 구간
WITH ranked AS (
    SELECT
        month_ym,
        month_date,
        gender,
        age_band,
        signup_cnt,
        sub_ride_cnt,
        total_ride_cnt,
        CASE WHEN signup_cnt > 0 THEN 1.0 * sub_ride_cnt / signup_cnt ELSE NULL END AS sub_rides_per_signup,
        CASE WHEN total_ride_cnt > 0 THEN 1.0 * sub_ride_cnt / total_ride_cnt ELSE NULL END AS same_month_subscription_share,
        NTILE(4) OVER (PARTITION BY month_ym ORDER BY signup_cnt) AS signup_quartile_in_month,
        NTILE(4) OVER (PARTITION BY month_ym ORDER BY CASE WHEN signup_cnt > 0 THEN 1.0 * sub_ride_cnt / signup_cnt ELSE NULL END) AS activation_quartile_in_month
    FROM mart_growth_month
    WHERE age_band <> '기타'
      AND LOWER(TRIM(COALESCE(gender, ''))) <> 'unknown'
      AND LOWER(TRIM(COALESCE(age_band, ''))) <> 'unknown'
)
SELECT
    month_ym,
    month_date,
    gender,
    age_band,
    signup_cnt,
    sub_ride_cnt,
    total_ride_cnt,
    ROUND(sub_rides_per_signup, 4) AS sub_rides_per_signup,
    ROUND(same_month_subscription_share, 4) AS same_month_subscription_share,
    signup_quartile_in_month,
    activation_quartile_in_month
FROM ranked
WHERE signup_quartile_in_month = 4
  AND activation_quartile_in_month <= 2
ORDER BY month_ym, signup_cnt DESC;
