-- 08_retention_analysis_queries.sql
-- Retention 분석 SQL
-- 사용 테이블: mart_growth_month

-- 1) 월별 전월 대비 정기권 이용 유지율 proxy
-- 월별 전체 흐름은 age_band='기타'도 실제 이용/가입 집계에 포함한다.
WITH duration AS(
    SELECT month_ym, month_date, gender, age_band, sub_ride_cnt, total_ride_cnt
    FROM mart_growth_month
    UNION ALL
    SELECT 
        month_ym, month_date, gender, age_band, 
        SUM(CASE WHEN pass_group = 'SUBSCRIPTION' THEN ride_cnt ELSE 0 END) AS sub_ride_cnt,
        SUM(ride_cnt) AS total_ride_cnt
    FROM stg_ride_month
    WHERE month_ym = 202312
    GROUP BY month_ym, month_date, gender, age_band
),
monthly AS (
    SELECT
        month_ym,
        month_date,
        SUM(sub_ride_cnt) AS sub_ride_cnt,
        SUM(total_ride_cnt) AS total_ride_cnt
    FROM duration
    WHERE LOWER(TRIM(COALESCE(gender, ''))) <> 'unknown'
      AND LOWER(TRIM(COALESCE(age_band, ''))) <> 'unknown'
    GROUP BY
        month_ym,
        month_date
),
windowed AS (
    SELECT
        month_ym,
        month_date,
        sub_ride_cnt,
        total_ride_cnt,
        LAG(sub_ride_cnt) OVER (ORDER BY month_ym) AS prev_month_sub_ride_cnt
    FROM monthly
)
SELECT
    month_ym,
    month_date,
    sub_ride_cnt,
    total_ride_cnt,
    prev_month_sub_ride_cnt,
    ROUND(
        CASE
            WHEN prev_month_sub_ride_cnt > 0
            THEN 1.0 * sub_ride_cnt / prev_month_sub_ride_cnt
            ELSE NULL
        END,
        4
    ) AS retention_proxy_mom,
    ROUND(
        CASE
            WHEN prev_month_sub_ride_cnt > 0
            THEN 1.0 * (sub_ride_cnt - prev_month_sub_ride_cnt) / prev_month_sub_ride_cnt
            ELSE NULL
        END,
        4
    ) AS mom_sub_ride_growth_rate
FROM windowed
WHERE month_ym BETWEEN 202401 AND 202512
ORDER BY month_ym;

-- 2) 최근 3개월 평균 대비 이번 달 정기권 이용
-- prev_3m_avg_sub_ride_cnt는 이번 달을 제외한 직전 3개월 평균이다.
WITH duration AS(
    SELECT month_ym, month_date, gender, age_band, sub_ride_cnt, total_ride_cnt
    FROM mart_growth_month
    UNION ALL
    SELECT 
        month_ym, month_date, gender, age_band, 
        SUM(CASE WHEN pass_group = 'SUBSCRIPTION' THEN ride_cnt ELSE 0 END) AS sub_ride_cnt,
        SUM(ride_cnt) AS total_ride_cnt
    FROM stg_ride_month
    WHERE month_ym BETWEEN 202310 AND 202312
    GROUP BY month_ym, month_date, gender, age_band
),
monthly AS (
    SELECT
        month_ym,
        month_date,
        SUM(sub_ride_cnt) AS sub_ride_cnt,
        SUM(total_ride_cnt) AS total_ride_cnt
    FROM duration
    WHERE LOWER(TRIM(COALESCE(gender, ''))) <> 'unknown'
      AND LOWER(TRIM(COALESCE(age_band, ''))) <> 'unknown'
    GROUP BY
        month_ym,
        month_date
),
windowed AS (
    SELECT
        month_ym,
        month_date,
        sub_ride_cnt,
        total_ride_cnt,
        AVG(sub_ride_cnt) OVER (
            ORDER BY month_ym
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev_3m_avg_sub_ride_cnt
    FROM monthly
)
SELECT
    month_ym,
    month_date,
    sub_ride_cnt,
    total_ride_cnt,
    ROUND(prev_3m_avg_sub_ride_cnt, 2) AS prev_3m_avg_sub_ride_cnt,
    ROUND(
        CASE
            WHEN prev_3m_avg_sub_ride_cnt > 0
            THEN 1.0 * sub_ride_cnt / prev_3m_avg_sub_ride_cnt
            ELSE NULL
        END,
        4
    ) AS rolling_3m_persistence,
    ROUND(
        CASE
            WHEN prev_3m_avg_sub_ride_cnt > 0
            THEN 1.0 * (sub_ride_cnt - prev_3m_avg_sub_ride_cnt) / prev_3m_avg_sub_ride_cnt
            ELSE NULL
        END,
        4
    ) AS current_vs_prev3m_growth_rate
FROM windowed
WHERE month_ym BETWEEN 202401 AND 202512
ORDER BY month_ym;

-- 3) 성별/연령대/월별 지속이용 proxy
-- 세그먼트 해석에서는 age_band='기타'를 제외한다.
WITH duration AS(
    SELECT month_ym, month_date, gender, age_band, sub_ride_cnt, total_ride_cnt
    FROM mart_growth_month
    UNION ALL
    SELECT 
        month_ym, month_date, gender, age_band, 
        SUM(CASE WHEN pass_group = 'SUBSCRIPTION' THEN ride_cnt ELSE 0 END) AS sub_ride_cnt,
        SUM(ride_cnt) AS total_ride_cnt
    FROM stg_ride_month
    WHERE month_ym BETWEEN 202310 AND 202312
    GROUP BY month_ym, month_date, gender, age_band
),
segment_month AS (
    SELECT
        month_ym,
        month_date,
        gender,
        age_band,
        SUM(sub_ride_cnt) AS sub_ride_cnt,
        SUM(total_ride_cnt) AS total_ride_cnt
    FROM duration
    WHERE age_band <> '기타'
      AND LOWER(TRIM(COALESCE(gender, ''))) <> 'unknown'
      AND LOWER(TRIM(COALESCE(age_band, ''))) <> 'unknown'
    GROUP BY
        month_ym,
        month_date,
        gender,
        age_band
),
windowed AS (
    SELECT
        month_ym,
        month_date,
        gender,
        age_band,
        sub_ride_cnt,
        total_ride_cnt,
        LAG(sub_ride_cnt) OVER (
            PARTITION BY gender, age_band
            ORDER BY month_ym
        ) AS prev_month_sub_ride_cnt,
        AVG(sub_ride_cnt) OVER (
            PARTITION BY gender, age_band
            ORDER BY month_ym
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev_3m_avg_sub_ride_cnt
    FROM segment_month
)
SELECT
    month_ym,
    month_date,
    gender,
    age_band,
    sub_ride_cnt,
    total_ride_cnt,
    prev_month_sub_ride_cnt,
    ROUND(
        CASE
            WHEN prev_month_sub_ride_cnt > 0
            THEN 1.0 * sub_ride_cnt / prev_month_sub_ride_cnt
            ELSE NULL
        END,
        4
    ) AS retention_proxy_mom,
    ROUND(prev_3m_avg_sub_ride_cnt, 2) AS prev_3m_avg_sub_ride_cnt,
    ROUND(
        CASE
            WHEN prev_3m_avg_sub_ride_cnt > 0
            THEN 1.0 * sub_ride_cnt / prev_3m_avg_sub_ride_cnt
            ELSE NULL
        END,
        4
    ) AS rolling_3m_persistence,
    ROUND(
        CASE
            WHEN total_ride_cnt > 0
            THEN 1.0 * sub_ride_cnt / total_ride_cnt
            ELSE NULL
        END,
        4
    ) AS same_segment_month_subscription_share
FROM windowed
WHERE month_ym BETWEEN 202401 AND 202512
ORDER BY
    gender,
    age_band,
    month_ym;

--4) 월별 전체 평균 대비 남성 20대 세그먼트 상대 지표
WITH base AS (
    SELECT
        month_ym,
        gender,
        age_band,
        retention_proxy_mom,
        rolling_3m_persistence
    FROM mart_growth_month
    WHERE age_band <> '기타'
      AND LOWER(TRIM(COALESCE(gender, ''))) <> 'unknown'
      AND LOWER(TRIM(COALESCE(age_band, ''))) <> 'unknown'
),
monthly_avg AS (
    SELECT
        month_ym,
        AVG(retention_proxy_mom) AS avg_retention_proxy_mom,
        AVG(rolling_3m_persistence) AS avg_rolling_3m_persistence
    FROM base
    GROUP BY month_ym
)
SELECT
    b.month_ym,
    b.gender,
    b.age_band,
    b.retention_proxy_mom,
    b.rolling_3m_persistence,
    ROUND(b.retention_proxy_mom - m.avg_retention_proxy_mom, 4) AS mom_gap_from_month_avg,
    ROUND(b.rolling_3m_persistence - m.avg_rolling_3m_persistence, 4) AS rolling_3m_gap_from_month_avg
FROM base b
JOIN monthly_avg m
    ON b.month_ym = m.month_ym
WHERE b.gender = 'M'
  AND b.age_band = '20대'
ORDER BY b.month_ym;

-- 5) 성별/연령대별 지속이용 차이 요약
WITH duration AS(
    SELECT month_ym, month_date, gender, age_band, sub_ride_cnt, total_ride_cnt
    FROM mart_growth_month
    UNION ALL
    SELECT 
        month_ym, month_date, gender, age_band, 
        SUM(CASE WHEN pass_group = 'SUBSCRIPTION' THEN ride_cnt ELSE 0 END) AS sub_ride_cnt,
        SUM(ride_cnt) AS total_ride_cnt
    FROM stg_ride_month
    WHERE month_ym BETWEEN 202310 AND 202312
    GROUP BY month_ym, month_date, gender, age_band
),
segment_month AS (
    SELECT
        month_ym,
        month_date,
        gender,
        age_band,
        SUM(sub_ride_cnt) AS sub_ride_cnt,
        SUM(total_ride_cnt) AS total_ride_cnt
    FROM duration
    WHERE age_band <> '기타'
      AND LOWER(TRIM(COALESCE(gender, ''))) <> 'unknown'
      AND LOWER(TRIM(COALESCE(age_band, ''))) <> 'unknown'
    GROUP BY
        month_ym,
        month_date,
        gender,
        age_band
),
windowed AS (
    SELECT
        month_ym,
        month_date,
        gender,
        age_band,
        sub_ride_cnt,
        total_ride_cnt,
        LAG(sub_ride_cnt) OVER (
            PARTITION BY gender, age_band
            ORDER BY month_ym
        ) AS prev_month_sub_ride_cnt,
        AVG(sub_ride_cnt) OVER (
            PARTITION BY gender, age_band
            ORDER BY month_ym
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev_3m_avg_sub_ride_cnt
    FROM segment_month
),
metrics AS (
    SELECT
        month_ym,
        month_date,
        gender,
        age_band,
        sub_ride_cnt,
        total_ride_cnt,
        CASE
            WHEN prev_month_sub_ride_cnt > 0
            THEN 1.0 * sub_ride_cnt / prev_month_sub_ride_cnt
            ELSE NULL
        END AS retention_proxy_mom,
        CASE
            WHEN prev_3m_avg_sub_ride_cnt > 0
            THEN 1.0 * sub_ride_cnt / prev_3m_avg_sub_ride_cnt
            ELSE NULL
        END AS rolling_3m_persistence,
        CASE
            WHEN total_ride_cnt > 0
            THEN 1.0 * sub_ride_cnt / total_ride_cnt
            ELSE NULL
        END AS subscription_share
    FROM windowed
    WHERE month_ym BETWEEN 202401 AND 202512
),
summary AS (
    SELECT
        gender,
        age_band,
        COUNT(*) AS active_month_count,
        SUM(sub_ride_cnt) AS total_sub_ride_cnt,
        ROUND(AVG(sub_ride_cnt), 2) AS avg_monthly_sub_ride_cnt,
        ROUND(AVG(retention_proxy_mom), 4) AS avg_retention_proxy_mom,
        ROUND(AVG(rolling_3m_persistence), 4) AS avg_rolling_3m_persistence,
        ROUND(AVG(subscription_share), 4) AS avg_subscription_share,
        ROUND(AVG(CASE WHEN retention_proxy_mom >= 1 THEN 1.0 ELSE 0.0 END), 4) AS retention_ge_1_share,
        ROUND(AVG(CASE WHEN rolling_3m_persistence >= 1 THEN 1.0 ELSE 0.0 END), 4) AS current_ge_prev3m_avg_share
    FROM metrics
    GROUP BY
        gender,
        age_band
),
ranked AS (
    SELECT
        *,
        NTILE(3) OVER (ORDER BY avg_monthly_sub_ride_cnt) AS volume_tertile,
        NTILE(3) OVER (ORDER BY avg_retention_proxy_mom) AS retention_tertile,
        NTILE(3) OVER (ORDER BY avg_rolling_3m_persistence) AS prev3m_tertile
    FROM summary
)
SELECT
    gender,
    age_band,
    active_month_count,
    total_sub_ride_cnt,
    avg_monthly_sub_ride_cnt,
    avg_retention_proxy_mom,
    avg_rolling_3m_persistence,
    avg_subscription_share,
    retention_ge_1_share,
    current_ge_prev3m_avg_share,
    volume_tertile,
    retention_tertile,
    prev3m_tertile,
    CASE
        WHEN volume_tertile = 3
         AND retention_tertile = 3
         AND prev3m_tertile = 3
        THEN '규모 큼 + 지속이용 강함'
        WHEN volume_tertile <= 2
         AND retention_tertile = 3
         AND prev3m_tertile = 3
        THEN '규모는 작지만 지속성 높음'
        WHEN volume_tertile = 3
         AND (retention_tertile = 1 OR prev3m_tertile = 1)
        THEN '규모는 크지만 지속성 약함'
        WHEN avg_subscription_share >= 0.9
        THEN '정기권 중심 지속 이용 성향'
        ELSE '일반'
    END AS retention_segment_type
FROM ranked
ORDER BY
    CASE
        WHEN volume_tertile = 3
         AND retention_tertile = 3
         AND prev3m_tertile = 3
        THEN 1
        WHEN volume_tertile <= 2
         AND retention_tertile = 3
         AND prev3m_tertile = 3
        THEN 2
        WHEN volume_tertile = 3
         AND (retention_tertile = 1 OR prev3m_tertile = 1)
        THEN 3
        WHEN avg_subscription_share >= 0.9
        THEN 4
        ELSE 5
    END,
    avg_retention_proxy_mom DESC,
    avg_rolling_3m_persistence DESC;

-- 6) 월별 약한 Retention 후보
-- 해당 월 정기권 이용 규모는 큰 편이지만 전월 대비 유지율이 낮은 세그먼트를 찾는다.
WITH duration AS(
    SELECT month_ym, month_date, gender, age_band, sub_ride_cnt, total_ride_cnt
    FROM mart_growth_month
    UNION ALL
    SELECT 
        month_ym, month_date, gender, age_band, 
        SUM(CASE WHEN pass_group = 'SUBSCRIPTION' THEN ride_cnt ELSE 0 END) AS sub_ride_cnt,
        SUM(ride_cnt) AS total_ride_cnt
    FROM stg_ride_month
    WHERE month_ym = 202312
    GROUP BY month_ym, month_date, gender, age_band
),
segment_month AS (
    SELECT
        month_ym,
        month_date,
        gender,
        age_band,
        SUM(sub_ride_cnt) AS sub_ride_cnt,
        SUM(total_ride_cnt) AS total_ride_cnt
    FROM duration
    WHERE age_band <> '기타'
      AND LOWER(TRIM(COALESCE(gender, ''))) <> 'unknown'
      AND LOWER(TRIM(COALESCE(age_band, ''))) <> 'unknown'
    GROUP BY
        month_ym,
        month_date,
        gender,
        age_band
),
windowed AS (
    SELECT
        month_ym,
        month_date,
        gender,
        age_band,
        sub_ride_cnt,
        total_ride_cnt,
        LAG(sub_ride_cnt) OVER (
            PARTITION BY gender, age_band
            ORDER BY month_ym
        ) AS prev_month_sub_ride_cnt
    FROM segment_month
),
ranked AS (
    SELECT
        *,
        CASE
            WHEN prev_month_sub_ride_cnt > 0
            THEN 1.0 * sub_ride_cnt / prev_month_sub_ride_cnt
            ELSE NULL
        END AS retention_proxy_mom,
        NTILE(4) OVER (
            PARTITION BY month_ym
            ORDER BY sub_ride_cnt
        ) AS sub_ride_volume_quartile_in_month,
        NTILE(4) OVER (
            PARTITION BY month_ym
            ORDER BY CASE
                WHEN prev_month_sub_ride_cnt > 0
                THEN 1.0 * sub_ride_cnt / prev_month_sub_ride_cnt
                ELSE NULL
            END
        ) AS retention_quartile_in_month
    FROM windowed
)
SELECT
    month_ym,
    month_date,
    gender,
    age_band,
    sub_ride_cnt,
    prev_month_sub_ride_cnt,
    ROUND(retention_proxy_mom, 4) AS retention_proxy_mom,
    sub_ride_volume_quartile_in_month,
    retention_quartile_in_month
FROM ranked
WHERE prev_month_sub_ride_cnt IS NOT NULL
  AND sub_ride_volume_quartile_in_month = 4
  AND retention_quartile_in_month <= 2
ORDER BY
    month_ym,
    sub_ride_cnt DESC;

-- 7) 실제 Retention 약화 후보
WITH duration AS(
    SELECT month_ym, month_date, gender, age_band, sub_ride_cnt, total_ride_cnt
    FROM mart_growth_month
    UNION ALL
    SELECT 
        month_ym, month_date, gender, age_band, 
        SUM(CASE WHEN pass_group = 'SUBSCRIPTION' THEN ride_cnt ELSE 0 END) AS sub_ride_cnt,
        SUM(ride_cnt) AS total_ride_cnt
    FROM stg_ride_month
    WHERE month_ym = 202312
    GROUP BY month_ym, month_date, gender, age_band
),
segment_month AS (
    SELECT
        month_ym,
        month_date,
        gender,
        age_band,
        SUM(sub_ride_cnt) AS sub_ride_cnt,
        SUM(total_ride_cnt) AS total_ride_cnt
    FROM duration
    WHERE age_band <> '기타'
      AND LOWER(TRIM(COALESCE(gender, ''))) <> 'unknown'
      AND LOWER(TRIM(COALESCE(age_band, ''))) <> 'unknown'
    GROUP BY
        month_ym,
        month_date,
        gender,
        age_band
),
windowed AS (
    SELECT
        month_ym,
        month_date,
        gender,
        age_band,
        sub_ride_cnt,
        total_ride_cnt,
        LAG(sub_ride_cnt) OVER (
            PARTITION BY gender, age_band
            ORDER BY month_ym
        ) AS prev_month_sub_ride_cnt
    FROM segment_month
),
ranked AS (
    SELECT
        *,
        CASE
            WHEN prev_month_sub_ride_cnt > 0
            THEN 1.0 * sub_ride_cnt / prev_month_sub_ride_cnt
            ELSE NULL
        END AS retention_proxy_mom,
        NTILE(4) OVER (
            PARTITION BY month_ym
            ORDER BY sub_ride_cnt
        ) AS sub_ride_volume_quartile_in_month,
        NTILE(4) OVER (
            PARTITION BY month_ym
            ORDER BY CASE
                WHEN prev_month_sub_ride_cnt > 0
                THEN 1.0 * sub_ride_cnt / prev_month_sub_ride_cnt
                ELSE NULL
            END
        ) AS retention_quartile_in_month
    FROM windowed
)
SELECT
    month_ym,
    month_date,
    gender,
    age_band,
    sub_ride_cnt,
    prev_month_sub_ride_cnt,
    ROUND(retention_proxy_mom, 4) AS retention_proxy_mom,
    sub_ride_volume_quartile_in_month,
    retention_quartile_in_month
FROM ranked
WHERE prev_month_sub_ride_cnt IS NOT NULL
  AND sub_ride_volume_quartile_in_month = 4
  AND retention_quartile_in_month <= 2
  AND retention_proxy_mom < 1
ORDER BY
    month_ym,
    sub_ride_cnt DESC;

