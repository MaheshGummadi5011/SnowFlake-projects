// PROJECT 3 : ENTERPRISE DATA PIPELINE WITH SNOWFLAKE

// PHASE 1 - ENVIRONMENT SETUP

// 1. Create Virtual Warehouse
CREATE OR REPLACE WAREHOUSE ENTERPRISE_WH
WITH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

USE WAREHOUSE ENTERPRISE_WH;

// 2. Create Database
CREATE OR REPLACE DATABASE ENTERPRISE_DB;

// 3. Create Schema
CREATE OR REPLACE SCHEMA SALES_SCHEMA;

USE DATABASE ENTERPRISE_DB;
USE SCHEMA SALES_SCHEMA;

// PHASE 2 - TABLE CREATION & DATA LOADING

// 1. Create File Format
CREATE OR REPLACE FILE FORMAT CSV_FORMAT
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"';

// 2. Create Internal Stage
CREATE OR REPLACE STAGE ENTERPRISE_STAGE
    FILE_FORMAT = CSV_FORMAT;

// 3. Create Tables
CREATE OR REPLACE TABLE CUSTOMERS (
    CUSTOMER_ID NUMBER,
    CUSTOMER_NAME VARCHAR(100),
    EMAIL VARCHAR(100),
    PHONE VARCHAR(20),
    CITY VARCHAR(50),
    STATE VARCHAR(50)
);

CREATE OR REPLACE TABLE PRODUCTS (
    PRODUCT_ID NUMBER,
    PRODUCT_NAME VARCHAR(100),
    CATEGORY VARCHAR(50),
    PRICE NUMBER(10,2)
);

CREATE OR REPLACE TABLE BRANCHES (
    BRANCH_ID NUMBER,
    BRANCH_NAME VARCHAR(100),
    CITY VARCHAR(50),
    STATE VARCHAR(50)
);

CREATE OR REPLACE TABLE SALES (
    SALE_ID NUMBER,
    CUSTOMER_ID NUMBER,
    PRODUCT_ID NUMBER,
    BRANCH_ID NUMBER,
    QUANTITY NUMBER,
    SALE_DATE DATE,
    TOTAL_AMOUNT NUMBER(10,2)
);

// 4. Load Data from Stage
COPY INTO CUSTOMERS FROM @ENTERPRISE_STAGE/customers.csv FILE_FORMAT = CSV_FORMAT;
COPY INTO PRODUCTS FROM @ENTERPRISE_STAGE/products.csv FILE_FORMAT = CSV_FORMAT;
COPY INTO BRANCHES FROM @ENTERPRISE_STAGE/branches.csv FILE_FORMAT = CSV_FORMAT;
COPY INTO SALES FROM @ENTERPRISE_STAGE/sales.csv FILE_FORMAT = CSV_FORMAT;

// 5. Verify Data
SELECT COUNT(*) AS CUSTOMER_COUNT FROM CUSTOMERS;
SELECT COUNT(*) AS PRODUCT_COUNT FROM PRODUCTS;
SELECT COUNT(*) AS BRANCH_COUNT FROM BRANCHES;
SELECT COUNT(*) AS SALES_COUNT FROM SALES;

// PHASE 3 - STREAMS & INCREMENTAL LOADING

// Task 10: Create a Stream on SALES table
CREATE OR REPLACE STREAM NEW_SALES_STREAM ON TABLE SALES;

// Task 11: Create a staging table for new sales
CREATE OR REPLACE TABLE NEW_SALES_STG (
    SALE_ID NUMBER,
    CUSTOMER_ID NUMBER,
    PRODUCT_ID NUMBER,
    BRANCH_ID NUMBER,
    QUANTITY NUMBER,
    SALE_DATE DATE,
    TOTAL_AMOUNT NUMBER(10,2)
);

// Task 12: Load new sales into staging
COPY INTO NEW_SALES_STG FROM @ENTERPRISE_STAGE/new_sales.csv FILE_FORMAT = CSV_FORMAT;

// Task 13: Merge new sales into main SALES table
MERGE INTO SALES AS tgt
USING NEW_SALES_STG AS src
ON tgt.sale_id = src.sale_id
WHEN NOT MATCHED THEN
    INSERT (sale_id, customer_id, product_id, branch_id, quantity, sale_date, total_amount)
    VALUES (src.sale_id, src.customer_id, src.product_id, src.branch_id, src.quantity, src.sale_date, src.total_amount);

// PHASE 4: Data Validation

// Task 14: Duplicate Sale IDs
SELECT sale_id, COUNT(*) AS occurrences
FROM SALES
GROUP BY sale_id
HAVING COUNT(*) > 1;

// Task 15: Sales referencing a Customer ID that doesn't exist
SELECT s.*
FROM SALES s
LEFT JOIN CUSTOMERS c ON s.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

// Task 16: Sales referencing a Product ID that doesn't exist
SELECT s.*
FROM SALES s
LEFT JOIN PRODUCTS p ON s.product_id = p.product_id
WHERE p.product_id IS NULL;

// Task 17: Count of newly inserted records (from this batch)
SELECT COUNT(*) AS "Newly Inserted Records"
FROM SALES
WHERE sale_id IN (SELECT sale_id FROM NEW_SALES_STG);

// PHASE 5: Time Travel

// Task 18: Delete one sales record
DELETE FROM SALES WHERE sale_id = 10;

// Capture the query ID of that DELETE immediately, in the same
// session, before running anything else - this is what Time
// Travel will roll back to.
SET query_id = (SELECT last_query_id());

// Task 19: Recover the deleted record
INSERT INTO SALES
SELECT * FROM SALES BEFORE (STATEMENT => $query_id)
WHERE sale_id = 10;

// Task 20: Verify recovery
SELECT * FROM SALES WHERE sale_id = 10;

// PHASE 6: Zero-Copy Clone

// Task 21: Create the clone (instant, no extra storage until
// either copy diverges from the other)
CREATE OR REPLACE TABLE SALES_TEST CLONE SALES;

// Task 22: Display cloned records
SELECT * FROM SALES_TEST;

// Task 23: Insert a new record into the CLONE only
INSERT INTO SALES_TEST (sale_id, customer_id, product_id, branch_id, quantity, sale_date, total_amount)
VALUES (999, 1, 101, 1, 1, '2026-07-15', 60000);

// Task 24: Verify the original SALES table is untouched
SELECT COUNT(*) AS "SALES row count"      FROM SALES;       -- unchanged
SELECT COUNT(*) AS "SALES_TEST row count" FROM SALES_TEST;  -- one more
SELECT * FROM SALES WHERE sale_id = 999;                     -- 0 rows

// PHASE 7: Task Automation

// Task 25: Create a Task to automate incremental loading daily.
// Tasks are created SUSPENDED by default, which is why Task 26
// exists as a separate step.
CREATE OR REPLACE TASK INCREMENTAL_LOAD_TASK
  WAREHOUSE = ENTERPRISE_WH
  SCHEDULE = 'USING CRON 0 0 * * * UTC'   -- runs daily at 00:00 UTC
AS
  MERGE INTO SALES AS tgt
  USING NEW_SALES_STREAM AS src
  ON tgt.sale_id = src.sale_id
  WHEN NOT MATCHED THEN
    INSERT (sale_id, customer_id, product_id, branch_id, quantity, sale_date, total_amount)
    VALUES (src.sale_id, src.customer_id, src.product_id, src.branch_id, src.quantity, src.sale_date, src.total_amount);

// Task 26: Resume it
ALTER TASK INCREMENTAL_LOAD_TASK RESUME;

// Task 27: Verify - check state and run history
SHOW TASKS LIKE 'INCREMENTAL_LOAD_TASK';

SELECT *
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
  TASK_NAME => 'INCREMENTAL_LOAD_TASK'
))
ORDER BY SCHEDULED_TIME DESC;

// IMPORTANT: suspend the task once you've captured your screenshot.
// A running scheduled task keeps consuming warehouse credits on
// your trial every day it fires, even with nothing new to merge.
ALTER TASK INCREMENTAL_LOAD_TASK SUSPEND;

// PHASE 8: Business Analytics

// Task 28: Customer Revenue Report
SELECT
  c.customer_id,
  c.customer_name,
  SUM(s.total_amount) AS total_revenue
FROM CUSTOMERS c
JOIN SALES s ON c.customer_id = s.customer_id
GROUP BY c.customer_id, c.customer_name
ORDER BY total_revenue DESC;

// Task 29: Branch Revenue Report
SELECT
  b.branch_id,
  b.branch_name,
  SUM(s.total_amount) AS total_revenue
FROM BRANCHES b
JOIN SALES s ON b.branch_id = s.branch_id
GROUP BY b.branch_id, b.branch_name
ORDER BY total_revenue DESC;

// Task 30: Product Revenue Report
SELECT
  p.product_id,
  p.product_name,
  SUM(s.total_amount) AS total_revenue
FROM PRODUCTS p
JOIN SALES s ON p.product_id = s.product_id
GROUP BY p.product_id, p.product_name
ORDER BY total_revenue DESC;

// Task 31: Monthly Revenue Report
SELECT
  DATE_TRUNC('MONTH', sale_date) AS sales_month,
  SUM(total_amount)              AS total_revenue
FROM SALES
GROUP BY sales_month
ORDER BY sales_month;

// Task 32: Highest Revenue Customer
SELECT
  c.customer_name,
  SUM(s.total_amount) AS total_revenue
FROM CUSTOMERS c
JOIN SALES s ON c.customer_id = s.customer_id
GROUP BY c.customer_name
ORDER BY total_revenue DESC
LIMIT 1;

// Task 33: Highest Revenue Branch
SELECT
  b.branch_name,
  SUM(s.total_amount) AS total_revenue
FROM BRANCHES b
JOIN SALES s ON b.branch_id = s.branch_id
GROUP BY b.branch_name
ORDER BY total_revenue DESC
LIMIT 1;

// Task 34: Top Five Products
SELECT
  p.product_name,
  SUM(s.total_amount) AS total_revenue
FROM PRODUCTS p
JOIN SALES s ON p.product_id = s.product_id
GROUP BY p.product_name
ORDER BY total_revenue DESC
LIMIT 5;

// (Bonus, matches Expected Output-14 "Top Five Customers")
SELECT
  c.customer_name,
  SUM(s.total_amount) AS total_revenue
FROM CUSTOMERS c
JOIN SALES s ON c.customer_id = s.customer_id
GROUP BY c.customer_name
ORDER BY total_revenue DESC
LIMIT 5;

// Task 35: Customer Purchase Frequency
SELECT
  c.customer_name,
  COUNT(s.sale_id) AS orders_placed
FROM CUSTOMERS c
JOIN SALES s ON c.customer_id = s.customer_id
GROUP BY c.customer_name
ORDER BY orders_placed DESC;

// Task 36: Running Revenue (cumulative, ordered by date)
SELECT
  sale_id,
  sale_date,
  total_amount,
  SUM(total_amount) OVER (
    ORDER BY sale_date, sale_id
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) AS running_revenue
FROM SALES
ORDER BY sale_date, sale_id;

// Task 37: Customer Ranking
SELECT
  customer_name,
  total_revenue,
  RANK() OVER (ORDER BY total_revenue DESC) AS customer_rank
FROM (
  SELECT c.customer_name, SUM(s.total_amount) AS total_revenue
  FROM CUSTOMERS c
  JOIN SALES s ON c.customer_id = s.customer_id
  GROUP BY c.customer_name
);

// PHASE 9: Views

// Task 38: Standard view
CREATE OR REPLACE VIEW CUSTOMER_REVENUE AS
SELECT
  c.customer_id,
  c.customer_name,
  SUM(s.total_amount) AS total_revenue
FROM CUSTOMERS c
JOIN SALES s ON c.customer_id = s.customer_id
GROUP BY c.customer_id, c.customer_name;

// Task 39: Branch revenue view (materialized views require
// Enterprise Edition; using a standard view instead).
CREATE OR REPLACE VIEW BRANCH_REVENUE AS
SELECT
  branch_id,
  SUM(total_amount) AS total_revenue
FROM SALES
GROUP BY branch_id;

// Task 40: Query both views
SELECT * FROM CUSTOMER_REVENUE
ORDER BY total_revenue DESC;

SELECT
  b.branch_name,
  r.total_revenue
FROM BRANCH_REVENUE r
JOIN BRANCHES b ON r.branch_id = b.branch_id
ORDER BY r.total_revenue DESC;
