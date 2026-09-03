// PROJECT 14A: E-Commerce Web Event Analytics
// Data Lake vs Warehouse Ingestion
// Module: 4.4a (Schema-on-Read vs Schema-on-Write)

// TASK 1: CREATE ENVIRONMENT & DATA LAKE INGESTION

CREATE OR REPLACE WAREHOUSE PROJECT14A_WH
WITH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

USE WAREHOUSE PROJECT14A_WH;

CREATE OR REPLACE DATABASE ECOMMERCE_ANALYTICS;

USE DATABASE ECOMMERCE_ANALYTICS;

CREATE OR REPLACE SCHEMA EVENT_PIPELINE;
USE SCHEMA EVENT_PIPELINE;

// Create Data Lake raw events table (VARIANT column for Schema-on-Read)
CREATE OR REPLACE TABLE LAKE_RAW_EVENTS (
    RAW_EVENT VARIANT,
    INGESTION_TIMESTAMP TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

// Ingest Batch 1 (Standard Structure)
INSERT INTO LAKE_RAW_EVENTS (RAW_EVENT) SELECT PARSE_JSON('{"event_id":"EVT-8001","timestamp":"2026-07-01T08:15:00Z","user_id":1001,"page":"checkout","action":"purchase","order":{"total":12500.00,"shipping_cost":250.00,"tax":625.00,"items":2}}');
INSERT INTO LAKE_RAW_EVENTS (RAW_EVENT) SELECT PARSE_JSON('{"event_id":"EVT-8002","timestamp":"2026-07-01T08:20:00Z","user_id":1002,"page":"product_detail","action":"view","order":null}');
INSERT INTO LAKE_RAW_EVENTS (RAW_EVENT) SELECT PARSE_JSON('{"event_id":"EVT-8003","timestamp":"2026-07-01T08:35:00Z","user_id":1003,"page":"cart","action":"add_to_cart","order":null}');
INSERT INTO LAKE_RAW_EVENTS (RAW_EVENT) SELECT PARSE_JSON('{"event_id":"EVT-8004","timestamp":"2026-07-01T09:10:00Z","user_id":1004,"page":"checkout","action":"purchase","order":{"total":45000.00,"shipping_cost":500.00,"tax":2250.00,"items":5}}');
INSERT INTO LAKE_RAW_EVENTS (RAW_EVENT) SELECT PARSE_JSON('{"event_id":"EVT-8005","timestamp":"2026-07-01T09:45:00Z","user_id":1001,"page":"product_detail","action":"view","order":null}');

// Ingest Batch 2 (Schema Evolution - New Fields: promo_code, discount_amount)
INSERT INTO LAKE_RAW_EVENTS (RAW_EVENT) SELECT PARSE_JSON('{"event_id":"EVT-8006","timestamp":"2026-07-02T10:00:00Z","user_id":1005,"page":"checkout","action":"purchase","order":{"total":18000.00,"shipping_cost":300.00,"tax":900.00,"items":3},"promo_code":"SUMMER20","discount_amount":3600.00}');
INSERT INTO LAKE_RAW_EVENTS (RAW_EVENT) SELECT PARSE_JSON('{"event_id":"EVT-8007","timestamp":"2026-07-02T10:15:00Z","user_id":1002,"page":"checkout","action":"purchase","order":{"total":8500.00,"shipping_cost":150.00,"tax":425.00,"items":1},"promo_code":"WELCOME10","discount_amount":850.00}');
INSERT INTO LAKE_RAW_EVENTS (RAW_EVENT) SELECT PARSE_JSON('{"event_id":"EVT-8008","timestamp":"2026-07-02T10:30:00Z","user_id":1006,"page":"cart","action":"add_to_cart","order":null,"promo_code":null,"discount_amount":0.00}');
INSERT INTO LAKE_RAW_EVENTS (RAW_EVENT) SELECT PARSE_JSON('{"event_id":"EVT-8009","timestamp":"2026-07-02T11:00:00Z","user_id":1003,"page":"checkout","action":"purchase","order":{"total":32000.00,"shipping_cost":400.00,"tax":1600.00,"items":4},"promo_code":"FESTIVE15","discount_amount":4800.00}');
INSERT INTO LAKE_RAW_EVENTS (RAW_EVENT) SELECT PARSE_JSON('{"event_id":"EVT-8010","timestamp":"2026-07-02T11:20:00Z","user_id":1007,"page":"product_detail","action":"view","order":null,"promo_code":null,"discount_amount":0.00}');

// Ingest Batch 3 (Edge Cases & Corrupted Record)
INSERT INTO LAKE_RAW_EVENTS (RAW_EVENT) SELECT PARSE_JSON('{"event_id":"EVT-8011","timestamp":"2026-07-03T12:00:00Z","user_id":1008,"page":"checkout","action":"purchase","order":{"total":0.00,"shipping_cost":0.00,"tax":0.00,"items":0},"promo_code":"FREEPASS","discount_amount":0.00}');

// Corrupted payload stored as raw string
INSERT INTO LAKE_RAW_EVENTS (RAW_EVENT) SELECT TO_VARIANT('INVALID_JSON_PAYLOAD_MALFORMED_STRING');

// Verify total count
SELECT COUNT(*) AS TOTAL_RAW_RECORD_CT FROM LAKE_RAW_EVENTS;

// TASK 2: SCHEMA-ON-READ EXTRACTION

SELECT
    RAW_EVENT:event_id::VARCHAR AS EVENT_ID,
    RAW_EVENT:timestamp::TIMESTAMP AS EVENT_TIME,
    RAW_EVENT:user_id::NUMBER AS USER_ID,
    RAW_EVENT:action::VARCHAR AS ACTION,
    RAW_EVENT:order.total::NUMBER(12,2) AS ORDER_TOTAL,
    RAW_EVENT:promo_code::VARCHAR AS PROMO_CODE
FROM LAKE_RAW_EVENTS
WHERE RAW_EVENT:event_id IS NOT NULL
ORDER BY EVENT_TIME;

// TASK 3: SCHEMA-ON-READ FINANCIAL ANALYSIS (NET_REVENUE for orders with total > 0)

SELECT
    RAW_EVENT:event_id::VARCHAR AS EVENT_ID,
    RAW_EVENT:order.total::NUMBER(12,2) AS ORDER_TOTAL,
    RAW_EVENT:order.shipping_cost::NUMBER(12,2) AS SHIPPING_COST,
    RAW_EVENT:order.tax::NUMBER(12,2) AS TAX,
    COALESCE(RAW_EVENT:discount_amount::NUMBER(12,2), 0) AS DISCOUNT_AMOUNT,
    RAW_EVENT:order.total::NUMBER(12,2)
        - RAW_EVENT:order.shipping_cost::NUMBER(12,2)
        - RAW_EVENT:order.tax::NUMBER(12,2)
        - COALESCE(RAW_EVENT:discount_amount::NUMBER(12,2), 0) AS NET_REVENUE
FROM LAKE_RAW_EVENTS
WHERE RAW_EVENT:order.total::NUMBER(12,2) > 0
ORDER BY EVENT_ID;

// TASK 4: FUNNEL & CONVERSION KEY METRICS

SELECT
    COUNT(*) AS TOTAL_EVENTS,
    SUM(CASE WHEN RAW_EVENT:action::VARCHAR = 'purchase' AND RAW_EVENT:order.total::NUMBER(12,2) > 0 THEN 1 ELSE 0 END) AS TOTAL_PURCHASES,
    ROUND(
        SUM(CASE WHEN RAW_EVENT:action::VARCHAR = 'purchase' AND RAW_EVENT:order.total::NUMBER(12,2) > 0 THEN 1 ELSE 0 END)
        * 100.0 / COUNT(*), 2
    ) AS CONVERSION_RATE_PCT,
    SUM(CASE WHEN RAW_EVENT:order.total::NUMBER(12,2) > 0 THEN RAW_EVENT:order.total::NUMBER(12,2) ELSE 0 END) AS TOTAL_GROSS_REVENUE,
    ROUND(
        SUM(CASE WHEN RAW_EVENT:order.total::NUMBER(12,2) > 0 THEN RAW_EVENT:order.total::NUMBER(12,2) ELSE 0 END)
        / NULLIF(SUM(CASE WHEN RAW_EVENT:action::VARCHAR = 'purchase' AND RAW_EVENT:order.total::NUMBER(12,2) > 0 THEN 1 ELSE 0 END), 0), 2
    ) AS AVERAGE_ORDER_VALUE
FROM LAKE_RAW_EVENTS
WHERE RAW_EVENT:event_id IS NOT NULL;

// TASK 5: DATA WAREHOUSE BACKFILL (Schema-on-Write)

CREATE OR REPLACE TABLE DW_STRUCTURED_EVENTS (
    EVENT_ID VARCHAR(50),
    EVENT_TIME TIMESTAMP,
    USER_ID NUMBER,
    PAGE VARCHAR(50),
    ACTION VARCHAR(50),
    ORDER_TOTAL NUMBER(12,2),
    SHIPPING_COST NUMBER(12,2),
    TAX NUMBER(12,2),
    ITEMS NUMBER,
    PROMO_CODE VARCHAR(50),
    DISCOUNT_AMOUNT NUMBER(12,2),
    NET_REVENUE NUMBER(12,2)
);

INSERT INTO DW_STRUCTURED_EVENTS
SELECT
    RAW_EVENT:event_id::VARCHAR,
    RAW_EVENT:timestamp::TIMESTAMP,
    RAW_EVENT:user_id::NUMBER,
    RAW_EVENT:page::VARCHAR,
    RAW_EVENT:action::VARCHAR,
    RAW_EVENT:order.total::NUMBER(12,2),
    RAW_EVENT:order.shipping_cost::NUMBER(12,2),
    RAW_EVENT:order.tax::NUMBER(12,2),
    RAW_EVENT:order.items::NUMBER,
    RAW_EVENT:promo_code::VARCHAR,
    COALESCE(RAW_EVENT:discount_amount::NUMBER(12,2), 0),
    CASE
        WHEN RAW_EVENT:order.total::NUMBER(12,2) > 0 THEN
            RAW_EVENT:order.total::NUMBER(12,2)
            - RAW_EVENT:order.shipping_cost::NUMBER(12,2)
            - RAW_EVENT:order.tax::NUMBER(12,2)
            - COALESCE(RAW_EVENT:discount_amount::NUMBER(12,2), 0)
        ELSE 0
    END
FROM LAKE_RAW_EVENTS
WHERE RAW_EVENT:event_id IS NOT NULL;

// Verify
SELECT COUNT(*) AS STORED_RECORDS_QTY, SUM(NET_REVENUE) AS TOTAL_NET_REVENUE
FROM DW_STRUCTURED_EVENTS;

// TASK 6: DATA INTEGRITY & ERROR QUARANTINE

CREATE OR REPLACE TABLE QUARANTINE_RAW_EVENTS (
    QUARANTINE_ID NUMBER IDENTITY(1,1),
    RAW_RECORD_TEXT VARCHAR,
    REASON VARCHAR(100),
    QUARANTINE_TIMESTAMP TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

// Identify and quarantine corrupt records (those without valid event_id)
INSERT INTO QUARANTINE_RAW_EVENTS (RAW_RECORD_TEXT, REASON)
SELECT
    RAW_EVENT::VARCHAR,
    'MALFORMED_JSON_BODY'
FROM LAKE_RAW_EVENTS
WHERE RAW_EVENT:event_id IS NULL;

// Verify quarantine
SELECT QUARANTINE_ID, RAW_RECORD_TEXT, REASON
FROM QUARANTINE_RAW_EVENTS;

// Remove quarantined records from lake
DELETE FROM LAKE_RAW_EVENTS
WHERE RAW_EVENT:event_id IS NULL;

// Final verification
SELECT 'LAKE_RAW_EVENTS' AS TABLE_NAME, COUNT(*) AS RECORD_COUNT FROM LAKE_RAW_EVENTS
UNION ALL SELECT 'DW_STRUCTURED_EVENTS', COUNT(*) FROM DW_STRUCTURED_EVENTS
UNION ALL SELECT 'QUARANTINE_RAW_EVENTS', COUNT(*) FROM QUARANTINE_RAW_EVENTS;