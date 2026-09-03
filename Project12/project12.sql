/* ============================================================
   PROJECT 12: Enterprise Retail Analytics DW - End-to-End
   Kimball & SCD Capstone

   NOTE: unlike Projects 1-7, this one uses direct INSERT ...
   VALUES statements for the dimension loads (matching the
   "number of rows inserted" wording in the brief's expected
   output, which is Snowflake's plain-INSERT status message, not
   COPY INTO's load-report format) rather than staging CSVs.
   ============================================================ */

/* ---------- TASK 1: Database and Schema ---------- */

CREATE OR REPLACE WAREHOUSE RETAIL_DW_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;

CREATE OR REPLACE DATABASE RETAIL_DW;

CREATE OR REPLACE SCHEMA RETAIL_DW.SALES_ANALYTICS;

USE WAREHOUSE RETAIL_DW_WH;
USE DATABASE RETAIL_DW;
USE SCHEMA SALES_ANALYTICS;

SELECT CURRENT_DATABASE() AS "Current database",
       CURRENT_SCHEMA()   AS "Current schema";

/* ---------- TASK 2: DIM_STORE ---------- */

CREATE OR REPLACE TABLE DIM_STORE (
  store_key     NUMBER AUTOINCREMENT START 1 INCREMENT 1 PRIMARY KEY,
  store_id      NUMBER,
  store_name    VARCHAR(100),
  city          VARCHAR(50),
  state         VARCHAR(50),
  store_manager VARCHAR(100)
);

/* ---------- TASK 3: DIM_PRODUCT ---------- */

CREATE OR REPLACE TABLE DIM_PRODUCT (
  product_key  NUMBER AUTOINCREMENT START 1 INCREMENT 1 PRIMARY KEY,
  product_id   NUMBER,
  product_name VARCHAR(100),
  category     VARCHAR(50),
  unit_price   NUMBER(10,2)
);

/* ---------- TASK 4: DIM_CUSTOMER_HYBRID ---------- */

CREATE OR REPLACE TABLE DIM_CUSTOMER_HYBRID (
  customer_key           NUMBER AUTOINCREMENT START 1 INCREMENT 1 PRIMARY KEY,
  customer_id            NUMBER,
  customer_name          VARCHAR(100),
  city                   VARCHAR(50),
  previous_city          VARCHAR(50),
  state                  VARCHAR(50),
  current_membership     VARCHAR(30),
  previous_membership    VARCHAR(30),
  historical_membership  VARCHAR(30),
  segment                VARCHAR(30),
  effective_date         DATE,
  expiry_date            DATE,
  is_current             BOOLEAN
);

/* ---------- TASK 5: Load Store and Product Data ---------- */

INSERT INTO DIM_STORE (store_id, store_name, city, state, store_manager) VALUES
(201, 'Metro Flagship',  'Hyderabad',  'Telangana',      'Rajesh Kumar'),
(202, 'Express Hub',     'Warangal',   'Telangana',      'Sita Sharma'),
(203, 'Coastal Center',  'Vijayawada', 'Andhra Pradesh', 'Vikram Rao');
-- expect: number of rows inserted: 3

INSERT INTO DIM_PRODUCT (product_id, product_name, category, unit_price) VALUES
(501, 'Laptop Pro',       'Electronics', 75000.00),
(502, 'Wireless Mouse',   'Electronics',  1500.00),
(503, 'Ergonomic Chair',  'Furniture',   12000.00),
(504, 'Coffee Maker',     'Appliances',   4500.00);
-- expect: number of rows inserted: 4

/* ---------- TASK 6: Load Initial Customer Data ---------- */

INSERT INTO DIM_CUSTOMER_HYBRID
  (customer_id, customer_name, city, previous_city, state,
   current_membership, previous_membership, historical_membership,
   segment, effective_date, expiry_date, is_current) VALUES
(101, 'Amit Sharma',  'Hyderabad',   NULL, 'Telangana',      'Silver', NULL, 'Silver', 'Regular', '2026-01-01', '9999-12-31', TRUE),
(102, 'Priya Reddy',  'Warangal',    NULL, 'Telangana',      'Gold',   NULL, 'Gold',   'Premium', '2026-01-01', '9999-12-31', TRUE),
(103, 'Rahul Verma',  'Vijayawada',  NULL, 'Andhra Pradesh', 'Silver', NULL, 'Silver', 'Regular', '2026-01-01', '9999-12-31', TRUE),
(104, 'Neha Patel',   'Hyderabad',   NULL, 'Telangana',      'Gold',   NULL, 'Gold',   'Premium', '2026-01-01', '9999-12-31', TRUE),
(105, 'Arjun Gupta',  'Nagpur',      NULL, 'Maharashtra',    'Bronze', NULL, 'Bronze', 'Regular', '2026-01-01', '9999-12-31', TRUE);
-- expect: number of rows inserted: 5

/* ---------- TASK 7: FACT_SALES ---------- */

CREATE OR REPLACE TABLE FACT_SALES (
  sales_key        NUMBER AUTOINCREMENT START 1 INCREMENT 1 PRIMARY KEY,
  transaction_id   VARCHAR(50),
  transaction_date DATE,
  customer_key     NUMBER,   -- FK -> DIM_CUSTOMER_HYBRID(customer_key)
  store_key        NUMBER,   -- FK -> DIM_STORE(store_key)
  product_key      NUMBER,   -- FK -> DIM_PRODUCT(product_key)
  quantity         NUMBER,
  unit_price       NUMBER(10,2),
  total_amount     NUMBER(12,2)
);

/* ---------- TASK 8: Q1 2026 Sales - dynamic key lookup at insert time ----------
   Each INSERT resolves customer_key/store_key/product_key by
   joining to the dimensions AS THEY STAND RIGHT NOW. Since this
   runs before any customer updates (Task 10), each customer still
   has exactly one row, so there's no ambiguity yet - but this is
   the exact mechanism that makes Task 13's join work later. ---------- */

-- TXN-1001: Customer 101, 1x Product 501, Store 201
INSERT INTO FACT_SALES
  (transaction_id, transaction_date, customer_key, store_key, product_key,
   quantity, unit_price, total_amount)
SELECT
  'TXN-1001', '2026-02-15', c.customer_key, s.store_key, p.product_key,
  1, p.unit_price, 1 * p.unit_price
FROM DIM_CUSTOMER_HYBRID c, DIM_STORE s, DIM_PRODUCT p
WHERE c.customer_id = 101 AND c.is_current = TRUE
  AND s.store_id = 201
  AND p.product_id = 501;
-- expect: number of rows inserted: 1

-- TXN-1002: Customer 103, 2x Product 502, Store 203
INSERT INTO FACT_SALES
  (transaction_id, transaction_date, customer_key, store_key, product_key,
   quantity, unit_price, total_amount)
SELECT
  'TXN-1002', '2026-03-10', c.customer_key, s.store_key, p.product_key,
  2, p.unit_price, 2 * p.unit_price
FROM DIM_CUSTOMER_HYBRID c, DIM_STORE s, DIM_PRODUCT p
WHERE c.customer_id = 103 AND c.is_current = TRUE
  AND s.store_id = 203
  AND p.product_id = 502;
-- expect: number of rows inserted: 1

/* ---------- TASK 9: Store Manager Update (SCD Type 1) ---------- */

UPDATE DIM_STORE
SET store_manager = 'Suresh Menon'
WHERE store_id = 201;
-- expect: number of rows updated: 1

SELECT store_id, store_name, city, state, store_manager
FROM DIM_STORE
WHERE store_id = 201;

/* ============================================================
   TASK 10: Multi-Attribute Customer Updates (same 3-step hybrid
   pattern as Project 11 - see that project's notes for why Step 3
   is needed and what it does)
   ============================================================ */

CREATE OR REPLACE TABLE CUSTOMER_UPDATES (
  customer_id     INT,
  customer_name   VARCHAR(100),
  city            VARCHAR(50),
  state           VARCHAR(50),
  membership      VARCHAR(30),
  segment         VARCHAR(30),
  effective_date  DATE
);
INSERT INTO CUSTOMER_UPDATES VALUES
(101, 'Amit Sharma', 'Bengaluru', 'Karnataka',  'Gold',     'Premium', '2026-04-01'),
(103, 'Rahul Verma', 'Chennai',   'Tamil Nadu', 'Gold',     'Premium', '2026-04-05'),
(104, 'Neha Patel',  'Hyderabad', 'Telangana',  'Platinum', 'Premium', '2026-04-10');

-- Step 1: expire current versions
UPDATE DIM_CUSTOMER_HYBRID t
SET
  expiry_date = DATEADD(day, -1, u.effective_date),
  is_current  = FALSE
FROM CUSTOMER_UPDATES u
WHERE t.customer_id = u.customer_id
  AND t.is_current = TRUE;
-- expect: number of rows updated: 1 (x3, one per customer - or a
-- single "3" if run as one batched statement, as here)

-- Step 2: insert new active versions
INSERT INTO DIM_CUSTOMER_HYBRID
  (customer_id, customer_name, city, previous_city, state,
   current_membership, previous_membership, historical_membership,
   segment, effective_date, expiry_date, is_current)
SELECT
  u.customer_id, u.customer_name,
  u.city                  AS city,
  old.city                AS previous_city,
  u.state                 AS state,
  u.membership              AS current_membership,
  old.current_membership    AS previous_membership,
  u.membership              AS historical_membership,
  u.segment,
  u.effective_date,
  '9999-12-31'::DATE        AS expiry_date,
  TRUE                      AS is_current
FROM CUSTOMER_UPDATES u
JOIN DIM_CUSTOMER_HYBRID old
  ON old.customer_id = u.customer_id
  AND old.is_current = FALSE
  AND old.expiry_date = DATEADD(day, -1, u.effective_date);
-- expect: number of rows inserted: 3

-- Step 3: synchronize CURRENT_MEMBERSHIP, PREVIOUS_MEMBERSHIP,
-- CITY, STATE across ALL rows (old and new) for changed customers
UPDATE DIM_CUSTOMER_HYBRID t
SET
  city                 = nv.city,
  previous_city        = ov.city,
  state                = nv.state,
  current_membership   = nv.membership,
  previous_membership  = ov.membership
FROM
  (SELECT customer_id, city, state, current_membership AS membership
   FROM DIM_CUSTOMER_HYBRID WHERE is_current = TRUE)  nv,
  (SELECT customer_id, city, current_membership AS membership
   FROM DIM_CUSTOMER_HYBRID WHERE is_current = FALSE) ov
WHERE t.customer_id = nv.customer_id
  AND t.customer_id = ov.customer_id;
-- expect: number of rows updated: 2 (x3 customers = 6 rows total,
-- or a single "6" if run batched, as here)

/* ---------- TASK 11: Q2 2026 Sale - binds to the NEW surrogate key ----------
   Because Task 10 already ran, is_current = TRUE now points at
   Customer 101's post-update row - this INSERT picks that up
   automatically with no extra logic needed. ---------- */

INSERT INTO FACT_SALES
  (transaction_id, transaction_date, customer_key, store_key, product_key,
   quantity, unit_price, total_amount)
SELECT
  'TXN-2001', '2026-04-15', c.customer_key, s.store_key, p.product_key,
  1, p.unit_price, 1 * p.unit_price
FROM DIM_CUSTOMER_HYBRID c, DIM_STORE s, DIM_PRODUCT p
WHERE c.customer_id = 101 AND c.is_current = TRUE
  AND s.store_id = 201
  AND p.product_id = 503;
-- expect: number of rows inserted: 1

/* ---------- TASK 12: Full Customer Dimension History ---------- */

SELECT
  customer_id, customer_name, city, previous_city,
  current_membership, previous_membership, historical_membership,
  segment, effective_date, expiry_date, is_current
FROM DIM_CUSTOMER_HYBRID
ORDER BY customer_id, effective_date;

/* ---------- TASK 13: Point-in-Time POS Analytics -----------
   The payoff query - see the explanation at the top of this
   script. No date filter needed: each fact row's customer_key
   already points at whichever dimension version was current when
   that sale happened. ---------- */

SELECT
  f.transaction_id,
  f.transaction_date,
  c.customer_id,
  c.customer_name,
  c.city                       AS current_city,
  c.historical_membership      AS membership_at_purchase,
  c.segment                    AS segment_at_purchase,
  s.store_name,
  p.product_name,
  f.total_amount
FROM FACT_SALES f
JOIN DIM_CUSTOMER_HYBRID c ON f.customer_key = c.customer_key
JOIN DIM_STORE           s ON f.store_key    = s.store_key
JOIN DIM_PRODUCT         p ON f.product_key  = p.product_key
WHERE c.customer_id = 101
ORDER BY f.transaction_date;

/* ---------- TASK 14: Warehouse Record Count Audit ---------- */

SELECT 'STORE DIMENSION RECORDS' AS metric, COUNT(*) AS value FROM DIM_STORE
UNION ALL
SELECT 'PRODUCT DIMENSION RECORDS', COUNT(*) FROM DIM_PRODUCT
UNION ALL
SELECT 'TOTAL CUSTOMER DIMENSION RECORDS', COUNT(*) FROM DIM_CUSTOMER_HYBRID
UNION ALL
SELECT 'CURRENT CUSTOMER RECORDS', SUM(IFF(is_current, 1, 0)) FROM DIM_CUSTOMER_HYBRID
UNION ALL
SELECT 'HISTORICAL CUSTOMER RECORDS', SUM(IFF(NOT is_current, 1, 0)) FROM DIM_CUSTOMER_HYBRID
UNION ALL
SELECT 'FACT SALES TRANSACTIONS', COUNT(*) FROM FACT_SALES;
-- expect: 3 / 4 / 8 / 5 / 3 / 3

/* ============================================================
   CLEANUP (run only after you're fully done + have screenshots)
   ============================================================
-- DROP DATABASE IF EXISTS RETAIL_DW;
-- DROP WAREHOUSE IF EXISTS RETAIL_DW_WH;
*/