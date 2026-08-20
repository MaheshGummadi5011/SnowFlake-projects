// PROJECT 5: Retail Sales Data Warehouse - Star Schema Design
// Topic: 4.1B – Star Schema

USE DATABASE RETAIL_DW;
USE SCHEMA RETAIL;
USE WAREHOUSE PROJECT5_WH;

// PHASE 1: ANALYZE BUSINESS REQUIREMENTS
// Business Process: Retail Sales Analytics
// Business Event: A customer purchases one or more products
//                 from a retail branch on a specific date.
// Reporting: Customer, Product, Branch, Date-based analytics

// PHASE 2 & 3: CREATE DIMENSION TABLES & FACT TABLE

// Dimension Table: DIM_CUSTOMER
CREATE OR REPLACE TABLE DIM_CUSTOMER (
    Customer_ID INT PRIMARY KEY,
    Customer_Name VARCHAR(100),
    City VARCHAR(50),
    State VARCHAR(50),
    Membership VARCHAR(20)
);

// Dimension Table: DIM_PRODUCT
CREATE OR REPLACE TABLE DIM_PRODUCT (
    Product_ID INT PRIMARY KEY,
    Product_Name VARCHAR(100),
    Category VARCHAR(50),
    Brand VARCHAR(50),
    Price INT
);

// Dimension Table: DIM_BRANCH
CREATE OR REPLACE TABLE DIM_BRANCH (
    Branch_ID INT PRIMARY KEY,
    Branch_Name VARCHAR(100),
    City VARCHAR(50),
    State VARCHAR(50),
    Region VARCHAR(20),
    Manager_Name VARCHAR(100)
);

// Dimension Table: DIM_DATE
CREATE OR REPLACE TABLE DIM_DATE (
    Date_ID INT PRIMARY KEY,
    Date DATE,
    Day INT,
    Day_Name VARCHAR(20),
    Week_No INT,
    Month VARCHAR(20),
    Quarter VARCHAR(5),
    Year INT,
    Is_Weekend VARCHAR(5)
);

// Fact Table: FACT_SALES
CREATE OR REPLACE TABLE FACT_SALES (
    Sale_ID INT PRIMARY KEY,
    Customer_ID INT REFERENCES DIM_CUSTOMER(Customer_ID),
    Product_ID INT REFERENCES DIM_PRODUCT(Product_ID),
    Branch_ID INT REFERENCES DIM_BRANCH(Branch_ID),
    Date_ID INT REFERENCES DIM_DATE(Date_ID),
    Quantity INT,
    Total_Amount INT
);

// PHASE 4: LOAD DATA INTO STAR SCHEMA

// Load DIM_CUSTOMER
INSERT INTO DIM_CUSTOMER
SELECT customer_id, customer_name, city, state, membership
FROM CUSTOMERS;

// Load DIM_PRODUCT
INSERT INTO DIM_PRODUCT
SELECT product_id, product_name, category, brand, price
FROM PRODUCTS;

// Load DIM_BRANCH
INSERT INTO DIM_BRANCH
SELECT branch_id, branch_name, city, state, region, manager_name
FROM BRANCHES;

// Load DIM_DATE
INSERT INTO DIM_DATE
SELECT date_id, date, day, day_name, week_no, month, quarter, year, is_weekend
FROM CALENDAR;

// Load FACT_SALES
INSERT INTO FACT_SALES
SELECT sale_id, customer_id, product_id, branch_id, date_id, quantity, total_amount
FROM SALES;

// PHASE 5: VALIDATE SCHEMA - ANALYTICAL REPORTS

// Verify row counts
SELECT 'DIM_CUSTOMER' AS table_name, COUNT(*) AS row_count FROM DIM_CUSTOMER
UNION ALL SELECT 'DIM_PRODUCT', COUNT(*) FROM DIM_PRODUCT
UNION ALL SELECT 'DIM_BRANCH', COUNT(*) FROM DIM_BRANCH
UNION ALL SELECT 'DIM_DATE', COUNT(*) FROM DIM_DATE
UNION ALL SELECT 'FACT_SALES', COUNT(*) FROM FACT_SALES;

// Report 1: Customer-wise Sales Report
SELECT c.Customer_Name, c.City, c.State, c.Membership,
       SUM(f.Quantity) AS Total_Qty,
       SUM(f.Total_Amount) AS Total_Revenue
FROM FACT_SALES f
JOIN DIM_CUSTOMER c ON f.Customer_ID = c.Customer_ID
GROUP BY c.Customer_Name, c.City, c.State, c.Membership
ORDER BY Total_Revenue DESC;

// Report 2: Product-wise Revenue Report
SELECT p.Product_Name, p.Category, p.Brand, p.Price,
       SUM(f.Quantity) AS Total_Qty_Sold,
       SUM(f.Total_Amount) AS Total_Revenue
FROM FACT_SALES f
JOIN DIM_PRODUCT p ON f.Product_ID = p.Product_ID
GROUP BY p.Product_Name, p.Category, p.Brand, p.Price
ORDER BY Total_Revenue DESC;

// Report 3: Branch-wise Revenue Report
SELECT b.Branch_Name, b.City, b.State, b.Region, b.Manager_Name,
       SUM(f.Quantity) AS Total_Qty_Sold,
       SUM(f.Total_Amount) AS Total_Revenue
FROM FACT_SALES f
JOIN DIM_BRANCH b ON f.Branch_ID = b.Branch_ID
GROUP BY b.Branch_Name, b.City, b.State, b.Region, b.Manager_Name
ORDER BY Total_Revenue DESC;

// Report 4: State-wise Revenue Report
SELECT b.State,
       SUM(f.Total_Amount) AS Total_Revenue,
       SUM(f.Quantity) AS Total_Qty_Sold
FROM FACT_SALES f
JOIN DIM_BRANCH b ON f.Branch_ID = b.Branch_ID
GROUP BY b.State
ORDER BY Total_Revenue DESC;

// Report 5: Monthly Revenue Report
SELECT d.Month, d.Year,
       SUM(f.Total_Amount) AS Monthly_Revenue,
       SUM(f.Quantity) AS Total_Qty_Sold
FROM FACT_SALES f
JOIN DIM_DATE d ON f.Date_ID = d.Date_ID
GROUP BY d.Month, d.Year
ORDER BY d.Year, d.Month;

// Report 6: Quarterly Revenue Report
SELECT d.Quarter, d.Year,
       SUM(f.Total_Amount) AS Quarterly_Revenue,
       SUM(f.Quantity) AS Total_Qty_Sold
FROM FACT_SALES f
JOIN DIM_DATE d ON f.Date_ID = d.Date_ID
GROUP BY d.Quarter, d.Year
ORDER BY d.Year, d.Quarter;

// Report 7: Top 10 Customers
SELECT c.Customer_Name, c.City, c.Membership,
       SUM(f.Total_Amount) AS Total_Spent
FROM FACT_SALES f
JOIN DIM_CUSTOMER c ON f.Customer_ID = c.Customer_ID
GROUP BY c.Customer_Name, c.City, c.Membership
ORDER BY Total_Spent DESC
LIMIT 10;

// Report 8: Top 10 Products
SELECT p.Product_Name, p.Category, p.Brand,
       SUM(f.Total_Amount) AS Total_Revenue
FROM FACT_SALES f
JOIN DIM_PRODUCT p ON f.Product_ID = p.Product_ID
GROUP BY p.Product_Name, p.Category, p.Brand
ORDER BY Total_Revenue DESC
LIMIT 10;

// Report 9: Top 10 Performing Branches
SELECT b.Branch_Name, b.City, b.Region,
       SUM(f.Total_Amount) AS Total_Revenue
FROM FACT_SALES f
JOIN DIM_BRANCH b ON f.Branch_ID = b.Branch_ID
GROUP BY b.Branch_Name, b.City, b.Region
ORDER BY Total_Revenue DESC
LIMIT 10;

// Report 10: Category-wise Revenue
SELECT p.Category,
       SUM(f.Total_Amount) AS Total_Revenue,
       SUM(f.Quantity) AS Total_Qty_Sold,
       COUNT(*) AS Total_Transactions
FROM FACT_SALES f
JOIN DIM_PRODUCT p ON f.Product_ID = p.Product_ID
GROUP BY p.Category
ORDER BY Total_Revenue DESC;

// Report 11: Customer Purchase Trend
SELECT c.Customer_Name, d.Month, d.Year,
       SUM(f.Total_Amount) AS Monthly_Spend
FROM FACT_SALES f
JOIN DIM_CUSTOMER c ON f.Customer_ID = c.Customer_ID
JOIN DIM_DATE d ON f.Date_ID = d.Date_ID
GROUP BY c.Customer_Name, d.Month, d.Year
ORDER BY c.Customer_Name, d.Year, d.Month;

// Report 12: Product Performance Dashboard
SELECT p.Product_Name, p.Category, p.Brand,
       SUM(f.Quantity) AS Units_Sold,
       SUM(f.Total_Amount) AS Revenue,
       ROUND(AVG(f.Total_Amount), 2) AS Avg_Sale_Value
FROM FACT_SALES f
JOIN DIM_PRODUCT p ON f.Product_ID = p.Product_ID
GROUP BY p.Product_Name, p.Category, p.Brand
ORDER BY Revenue DESC;

// Report 13: Branch Performance Dashboard
SELECT b.Branch_Name, b.Region, b.Manager_Name,
       COUNT(*) AS Total_Transactions,
       SUM(f.Quantity) AS Units_Sold,
       SUM(f.Total_Amount) AS Revenue,
       ROUND(AVG(f.Total_Amount), 2) AS Avg_Transaction_Value
FROM FACT_SALES f
JOIN DIM_BRANCH b ON f.Branch_ID = b.Branch_ID
GROUP BY b.Branch_Name, b.Region, b.Manager_Name
ORDER BY Revenue DESC;

// Report 14: Regional Sales Analysis
SELECT b.Region,
       COUNT(DISTINCT b.Branch_ID) AS Num_Branches,
       SUM(f.Total_Amount) AS Total_Revenue,
       SUM(f.Quantity) AS Total_Qty_Sold,
       ROUND(AVG(f.Total_Amount), 2) AS Avg_Sale_Amount
FROM FACT_SALES f
JOIN DIM_BRANCH b ON f.Branch_ID = b.Branch_ID
GROUP BY b.Region
ORDER BY Total_Revenue DESC;

// Report 15: Sales Trend Analysis (Weekend vs Weekday)
SELECT d.Is_Weekend,
       COUNT(*) AS Total_Transactions,
       SUM(f.Total_Amount) AS Total_Revenue,
       ROUND(AVG(f.Total_Amount), 2) AS Avg_Revenue_Per_Sale
FROM FACT_SALES f
JOIN DIM_DATE d ON f.Date_ID = d.Date_ID
GROUP BY d.Is_Weekend
ORDER BY d.Is_Weekend;

// PHASE 6: STAR SCHEMA METADATA & ADVANTAGES
