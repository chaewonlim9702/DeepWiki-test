WITH
  '{{dateRange.value.start}}' AS start_date,
  '{{dateRange.value.end}}' AS end_date,
  replace('{{dateRange.value.end}}', '-', '') AS end_date_str,
sale_raw AS (
    SELECT
        A.sty_cd AS sty_cd,
        max(A.sty_nm) AS sty_nm,
        A.col_cd AS col_cd,
        max(A.col_nm) AS col_nm,
        max(A.year_cd) AS year_cd,
        max(A.sesn_cd) AS sesn_cd,
        sum(A.sale_qty) AS sale_qty,
        sum(A.sale_amt) AS sale_amt
    FROM agabang_dw.daily_sales_by_color AS A
    WHERE 1=1
        AND sale_dt BETWEEN start_date AND end_date
        AND concat(A.year_cd, A.sesn_cd) IN ({{var_target_season_code?.value}})
        AND toInt8(A.br_cd) = {{ var_brand_code.value }}
    GROUP BY A.sty_cd, A.col_cd
),
sldsinfo_col AS (
    SELECT
        S.sty_cd AS sty_cd,
        S.col_cd AS col_cd,
        argMax(S.sale_prce, S.str_dt) AS info_sale_prce,
        argMax(S.str_dt, S.str_dt) AS info_str_dt
    FROM agabang.sldsinfo AS S
    INNER JOIN keys_small AS K
        ON S.sty_cd = K.sty_cd AND S.col_cd = K.col_cd
    WHERE 1=1
        AND S.comp_cd = 'AG001'
        AND S.shop_cd = '*'
        AND S.col_cd != '*'
        AND S.str_dt <= end_date_str
        AND S.end_dt >= end_date_str
    GROUP BY S.sty_cd, S.col_cd
),
sldsinfo_star AS (
    SELECT
        S.sty_cd AS sty_cd,
        argMax(S.sale_prce, S.str_dt) AS info_sale_prce,
        argMax(S.str_dt, S.str_dt) AS info_str_dt
    FROM agabang.sldsinfo AS S
    INNER JOIN (SELECT DISTINCT sty_cd FROM keys_small) AS K
        ON S.sty_cd = K.sty_cd
    WHERE 1=1
        AND S.comp_cd = 'AG001'
        AND S.shop_cd = '*'
        AND S.col_cd = '*'
        AND S.str_dt <= end_date_str
        AND S.end_dt >= end_date_str
    GROUP BY S.sty_cd
),
sldsprce_col AS (
    SELECT
        P.sty_cd AS sty_cd,
        P.col_cd AS col_cd,
        argMax(P.sale_prce, P.str_dt) AS prce_sale_prce,
        argMax(P.str_dt, P.str_dt) AS prce_str_dt
    FROM agabang.sldsprce AS P
    INNER JOIN keys_small AS K
        ON P.sty_cd = K.sty_cd AND P.col_cd = K.col_cd
    WHERE 1=1
        AND P.comp_cd = 'AG001'
        AND P.shop_cd = '*'
        AND P.col_cd != '*'
        AND P.str_dt <= end_date_str
        AND P.end_dt >= end_date_str
    GROUP BY P.sty_cd, P.col_cd
),
sldsprce_star AS (
    SELECT
        P.sty_cd AS sty_cd,
        argMax(P.sale_prce, P.str_dt) AS prce_sale_prce,
        argMax(P.str_dt, P.str_dt) AS prce_str_dt
    FROM agabang.sldsprce AS P
    INNER JOIN (SELECT DISTINCT sty_cd FROM keys_small) AS K
        ON P.sty_cd = K.sty_cd
    WHERE 1=1
        AND P.comp_cd = 'AG001'
        AND P.shop_cd = '*'
        AND P.col_cd = '*'
        AND P.str_dt <= end_date_str
        AND P.end_dt >= end_date_str
    GROUP BY P.sty_cd
),
prices_at_period AS (
    SELECT
        K.sty_cd AS sty_cd,
        K.col_cd AS col_cd,
        coalesce(IC.info_str_dt, IS.info_str_dt) AS info_str_dt,
        coalesce(IC.info_sale_prce, IS.info_sale_prce) AS info_sale_prce,
        coalesce(PC.prce_str_dt, PS.prce_str_dt) AS prce_str_dt,
        coalesce(PC.prce_sale_prce, PS.prce_sale_prce) AS prce_sale_prce
    FROM keys_small AS K
    LEFT JOIN sldsinfo_col AS IC
        ON K.sty_cd = IC.sty_cd AND K.col_cd = IC.col_cd
    LEFT JOIN sldsinfo_star AS IS
        ON K.sty_cd = IS.sty_cd
    LEFT JOIN sldsprce_col AS PC
        ON K.sty_cd = PC.sty_cd AND K.col_cd = PC.col_cd
    LEFT JOIN sldsprce_star AS PS
        ON K.sty_cd = PS.sty_cd
),
sale_item AS (
    SELECT
        A.*,
        B.item_md_category_id,
        B.cat_raw_nm AS cat_raw_nm,
        B.cat_nm AS cat_nm
    FROM sale_raw AS A
    JOIN agabang_dw.retooldb_item_md_info AS B
      ON A.sty_cd = B.sty_cd
      AND toInt8(B.br_cd) = {{ var_brand_code.value }}
),
dsrealsum AS (
    SELECT
        A.sty_cd AS sty_cd,
        A.col_cd AS col_cd,
        min(CASE WHEN A.wh_cd = '1000' THEN toDate(A.fin_date) ELSE NULL END) AS fin_date,
        min(CASE WHEN A.wh_cd = '1000' THEN toDate(A.fout_date) ELSE NULL END) AS fout_date,
        coalesce(sum(A.in_qty - A.in_rt_qty), 0) AS tot_in_qty,
        coalesce(sum(A.out_qty - A.rtn_qty), 0) AS out_qty
    FROM agabang.dsrealsum AS A
    WHERE 1=1
        AND A.comp_cd = 'AG001'
        AND toInt8(A.br_cd) = {{ var_brand_code.value }}
    GROUP BY A.sty_cd, A.col_cd
),
plstycd AS (
    SELECT
        A.sty_cd AS sty_cd,
        max(A.tag_prce) AS tag_prce
    FROM agabang.plstycd AS A
    WHERE 1=1
        AND A.comp_cd = 'AG001'
        AND toInt8(A.br_cd) = {{ var_brand_code.value }}
    GROUP BY A.sty_cd
),
slstysum AS (
    SELECT
        A.sty_cd AS sty_cd,
        A.col_cd AS col_cd,
        sum(A.sale_qty) AS tot_sale_qty,
        sum(A.sale_amt) AS tot_sale_amt
    FROM agabang_dw.daily_sales_by_color AS A
    WHERE 1=1
        AND A.comp_cd = 'AG001'
        AND substring(A.sty_cd, 1, 2) = lpad(cast({{ var_brand_code.value }} as text), 2, '0')
        AND A.sale_dt <= end_date
    GROUP BY A.sty_cd, A.col_cd
),
final_base AS (
    SELECT
        A.item_md_category_id,
        A.cat_raw_nm AS cat_raw_nm,
        A.cat_nm AS cat_nm,
        A.sty_cd AS sty_cd,
        A.sty_nm AS sty_nm,
        A.col_cd AS col_cd,
        A.col_nm AS col_nm,
        A.cat_nm as cat_nm_dup,
        A.sale_qty AS int_sale_qty,
        A.sale_amt AS int_sale_amt,
        A.sale_qty / nullif(B.tot_in_qty, 0) AS int_sale_rate,
        B.tot_in_qty AS tot_in_qty,
        D.tot_sale_qty AS tot_sale_qty,
        D.tot_sale_amt AS tot_sale_amt,
        D.tot_sale_qty / nullif(B.tot_in_qty, 0)  as cum_sales_rate,
        C.tag_prce AS tag_prce,
        B.fin_date AS fin_date,
        B.fout_date AS fout_date
    FROM sale_item AS A
    LEFT JOIN dsrealsum AS B
      ON A.sty_cd = B.sty_cd AND A.col_cd = B.col_cd
    LEFT JOIN plstycd AS C
      ON A.sty_cd = C.sty_cd
    LEFT JOIN slstysum AS D
      ON A.sty_cd = D.sty_cd AND A.col_cd = D.col_cd
    WHERE A.item_md_category_id = {{ sel_category.value }}
),
best_base AS (
  SELECT *
  FROM (
      SELECT
          row_number() OVER (PARTITION BY item_md_category_id ORDER BY int_sale_qty DESC) AS sale_rank,
          *
      FROM final_base AS A
      WHERE 1=1
          AND A.int_sale_qty > 0
  )
  WHERE 1=1
      AND sale_rank <= {{ select_best_list_count.value }}
),
worst_base AS (
  SELECT *
  FROM (
      SELECT
          row_number() OVER (PARTITION BY item_md_category_id ORDER BY int_sale_qty ASC) AS sale_rank,
          *
      FROM final_base AS A
      WHERE 1=1
        AND (tot_sale_qty / nullif(tot_in_qty, 0)) < {{ select_exclude_rate.value }}
        AND date_diff('day', fout_date, today(), 'Asia/Seoul') >= {{ select_exclude_day.value }}
  )
  WHERE 1=1
      AND sale_rank <= {{ select_worst_list_count.value }}
),
keys_small AS (
  SELECT DISTINCT sty_cd, col_cd FROM best_base
  UNION ALL
  SELECT DISTINCT sty_cd, col_cd FROM worst_base
),
final_price AS (
    SELECT
        K.sty_cd AS sty_cd,
        K.col_cd AS col_cd,
        C.tag_prce AS tag_price,
        CASE
            WHEN (PA.info_str_dt IS NOT NULL) AND (PA.prce_str_dt IS NOT NULL) AND (toString(PA.info_str_dt) >= toString(PA.prce_str_dt)) THEN PA.info_sale_prce
            WHEN (PA.info_str_dt IS NOT NULL) AND (PA.prce_str_dt IS NOT NULL) AND (toString(PA.info_str_dt) <  toString(PA.prce_str_dt)) THEN PA.prce_sale_prce
            WHEN (PA.info_str_dt IS NOT NULL) AND (PA.prce_str_dt IS NULL) THEN PA.info_sale_prce
            WHEN (PA.info_str_dt IS NULL) AND (PA.prce_str_dt IS NOT NULL) THEN PA.prce_sale_prce
            ELSE C.tag_prce
        END AS f_sale_prce,
        CASE WHEN C.tag_prce = 0 OR C.tag_prce IS NULL THEN 0
             ELSE round(((C.tag_prce -
                 CASE
                    WHEN (PA.info_str_dt IS NOT NULL) AND (PA.prce_str_dt IS NOT NULL) AND (toString(PA.info_str_dt) >= toString(PA.prce_str_dt)) THEN PA.info_sale_prce
                    WHEN (PA.info_str_dt IS NOT NULL) AND (PA.prce_str_dt IS NOT NULL) AND (toString(PA.info_str_dt) <  toString(PA.prce_str_dt)) THEN PA.prce_sale_prce
                    WHEN (PA.info_str_dt IS NOT NULL) AND (PA.prce_str_dt IS NULL) THEN PA.info_sale_prce
                    WHEN (PA.info_str_dt IS NULL) AND (PA.prce_str_dt IS NOT NULL) THEN PA.prce_sale_prce
                    ELSE C.tag_prce
                 END) / C.tag_prce) * 100, 0)
        END AS dc_rate
    FROM keys_small AS K
    LEFT JOIN prices_at_period AS PA
        ON K.sty_cd = PA.sty_cd AND K.col_cd = PA.col_cd
    LEFT JOIN plstycd AS C
        ON K.sty_cd = C.sty_cd
),
best AS (
  SELECT BB.*, FP.tag_price, FP.dc_rate, FP.f_sale_prce,
         BB.tag_prce / nullif(FP.f_sale_prce, 0) AS multi_rate
  FROM best_base BB
  LEFT JOIN final_price FP
    ON BB.sty_cd = FP.sty_cd AND BB.col_cd = FP.col_cd
),
worst AS (
  SELECT WB.*, FP.tag_price, FP.dc_rate, FP.f_sale_prce,
         WB.tag_prce / nullif(FP.f_sale_prce, 0) AS multi_rate
  FROM worst_base WB
  LEFT JOIN final_price FP
    ON WB.sty_cd = FP.sty_cd AND WB.col_cd = FP.col_cd
)
SELECT
  'BEST' AS sort,
  *
FROM best
UNION ALL
SELECT
  'WORST' AS sort,
  *
FROM worst