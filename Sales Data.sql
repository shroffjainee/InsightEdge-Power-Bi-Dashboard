SELECT TOP 100 * FROM raw_ecommerce_data;

SELECT Order_ID, COUNT(*) AS Count
FROM raw_ecommerce_data
GROUP BY Order_ID
HAVING COUNT(*) > 1;



--Staging Table (Copy Raw Data)
SELECT * INTO ecommerce_staging FROM raw_ecommerce_data;
ALTER TABLE ecommerce_staging 
ALTER COLUMN order_date DATE;
SELECT * FROM ecommerce_staging
ALTER TABLE ecommerce_staging 
ALTER COLUMN delivery_date DATE;
SELECT COLUMN_NAME, DATA_TYPE 
FROM INFORMATION_SCHEMA.COLUMNS 
WHERE TABLE_NAME = 'ecommerce_staging' AND COLUMN_NAME IN ('order_date', 'delivery_date');

--Convert Date Formats
UPDATE ecommerce_staging
SET order_date = TRY_CONVERT(DATE, order_date, 105)
WHERE TRY_CONVERT(nvarchar(20), order_date, 105) IS NOT NULL;

UPDATE ecommerce_staging
SET delivery_date = TRY_CONVERT(DATE, delivery_date, 105)
WHERE TRY_CONVERT(nvarchar(20), delivery_date, 105) IS NOT NULL;
select * from ecommerce_staging;


-- remove rows with null values 
DELETE FROM ecommerce_staging
WHERE order_date is NULL OR delivery_date is NULL;


--Handle Missing Values
UPDATE ecommerce_staging
SET customer_id = COALESCE(customer_id, 'Unknown');

UPDATE ecommerce_staging
SET discount = COALESCE(discount, 0);

UPDATE ecommerce_staging
SET return_status = COALESCE(return_status, 'Not Returned');

--Fix Negative Discount Values
UPDATE ecommerce_staging
SET discount = ABS(discount);

--Swap Incorrect Order & Delivery Dates
UPDATE ecommerce_staging
SET order_date = delivery_date, delivery_date = order_date
WHERE order_date > delivery_date;

--Remove Duplicates Using ROW_NUMBER()
--check duplicates 
SELECT order_id, customer_id, order_date, COUNT(*)
FROM ecommerce_staging
GROUP BY order_id, customer_id, order_date
HAVING COUNT(*) > 1;


--remove duplicates
WITH deduped AS (
    SELECT order_id, customer_id, order_date,
           ROW_NUMBER() OVER (
               PARTITION BY order_id 
               ORDER BY ISNULL(customer_id, 'ZZZZZZ') ASC, ISNULL(order_date, '9999-12-31') ASC
           ) AS row_num
    FROM ecommerce_staging
)
DELETE FROM ecommerce_staging
WHERE order_id IN (
    SELECT order_id FROM deduped WHERE row_num > 1
);


--check if duplicates are removed 
SELECT order_id, COUNT(*) as num_of_duplicates
FROM ecommerce_staging 
GROUP BY order_id
HAVING COUNT(*) > 1;

-- to check the number of rows 
SELECT COUNT(*) as after from ecommerce_staging;
select count(*) as before from raw_ecommerce_data;


--Standardize Text Formatting
UPDATE ecommerce_staging
SET category = UPPER(TRIM(category)),
    sub_category = UPPER(TRIM(sub_category)),
    payment_method = UPPER(TRIM(payment_method)),
    city = UPPER(TRIM(city)),
    state = UPPER(TRIM(state)),
    region = UPPER(TRIM(region));

--Create Final Cleaned Table
SELECT * INTO ecommerce_cleaned FROM ecommerce_staging;


--Create Fact and Dimension Tables (Star Schema)
-- Customers Dimension
CREATE TABLE dim_customers (
    customer_id NVARCHAR(50) PRIMARY KEY,
    customer_name VARCHAR(255),
    city VARCHAR(255),
    state VARCHAR(255),
    region VARCHAR(255)
);
 
-- Products Dimension
CREATE TABLE dim_products (
    product_id NVARCHAR(50) PRIMARY KEY,
    product_name VARCHAR(255),
    category VARCHAR(100),
    sub_category VARCHAR(100)
);

-- Salesperson Dimension
CREATE TABLE dim_salesperson (
    salesperson_id NVARCHAR(50) PRIMARY KEY,
    salesperson_name VARCHAR(255)
);

-- Date Dimension
CREATE TABLE dim_dates (
    date_id INT PRIMARY KEY IDENTITY(1,1), -- Surrogate Key (Auto-Increment)
    order_date DATE,
    delivery_date DATE,
    year INT,
    month INT,
    quarter INT
);

-- Fact Table (Sales Transactions)
SELECT e.order_date, d.date_id
FROM ecommerce_staging e
LEFT JOIN dim_dates d ON e.order_date = d.order_date
WHERE d.date_id IS NULL;



CREATE TABLE fact_sales (
    order_id NVARCHAR(50), 
    customer_id NVARCHAR(50),
    product_id NVARCHAR(50),
    salesperson_id NVARCHAR(50),
    date_id INT, 
    order_quantity INT,
    unit_price DECIMAL(10,2),
    total_price DECIMAL(12,2),
    discount DECIMAL(5,2),
    return_status VARCHAR(50),
    FOREIGN KEY (customer_id) REFERENCES dim_customers(customer_id),
    FOREIGN KEY (product_id) REFERENCES dim_products(product_id),
    FOREIGN KEY (salesperson_id) REFERENCES dim_salesperson(salesperson_id),
    FOREIGN KEY (date_id) REFERENCES dim_dates(date_id) 
);



--checking for null values 
SELECT COUNT(*) AS NullCustomerIDs 
FROM ecommerce_staging 
WHERE customer_id IS NULL;

--fix the null values
DELETE FROM ecommerce_staging WHERE customer_id IS NULL;

UPDATE ecommerce_staging 
SET customer_id = 'UNKNOWN' 
WHERE customer_id IS NULL;


-- Insert data into dim_customers
--Remove Duplicates Before Insert
WITH RankedCustomers AS (
    SELECT 
        customer_id, 
        customer_name, 
        city, 
        state, 
        region,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date DESC) AS rn
    FROM ecommerce_staging
    WHERE customer_id IS NOT NULL
)
DELETE FROM RankedCustomers WHERE rn > 1;


--Insert Data Without Duplicates
INSERT INTO dim_customers (customer_id, customer_name, city, state, region)
SELECT DISTINCT customer_id, customer_name, city, state, region
FROM ecommerce_staging
WHERE customer_id IS NOT NULL
AND customer_id NOT IN (SELECT customer_id FROM dim_customers);



SELECT customer_id, COUNT(*)
FROM dim_customers
GROUP BY customer_id
HAVING COUNT(*) > 1;


-- Insert data into dim_products
WITH RankedProducts AS (
    SELECT 
        product_id, 
        product_name, 
        category, 
        sub_category,
        ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY order_date DESC) AS rn
    FROM ecommerce_staging
    WHERE product_id IS NOT NULL
)
INSERT INTO dim_products (product_id, product_name, category, sub_category)
SELECT product_id, product_name, category, sub_category
FROM RankedProducts
WHERE rn = 1;

--adding unit_price column
ALTER TABLE dim_products  
ADD unit_price MONEY;  

--Update unit_price in dim_products from ecommerce_staging
WITH LatestPrices AS (
    SELECT 
        product_id, 
        unit_price,
        ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY order_date DESC) AS rn
    FROM ecommerce_staging
    WHERE product_id IS NOT NULL AND unit_price IS NOT NULL
)
UPDATE dim_products  
SET unit_price = LP.unit_price  
FROM dim_products dp  
JOIN LatestPrices LP ON dp.product_id = LP.product_id  
WHERE LP.rn = 1;


-- Insert data into dim_salesperson
WITH RankedSalespersons AS (
    SELECT 
        salesperson_id, 
        salesperson_name,
        ROW_NUMBER() OVER (PARTITION BY salesperson_id ORDER BY order_date DESC) AS rn
    FROM ecommerce_staging
    WHERE salesperson_id IS NOT NULL
)
INSERT INTO dim_salesperson (salesperson_id, salesperson_name)
SELECT salesperson_id, salesperson_name
FROM RankedSalespersons
WHERE rn = 1;


-- Insert data into dim_dates
INSERT INTO dim_dates (order_date, delivery_date, year, month, quarter)
SELECT DISTINCT 
       TRY_CAST(order_date AS DATE), 
       TRY_CAST(delivery_date AS DATE), 
       YEAR(TRY_CAST(order_date AS DATE)), 
       MONTH(TRY_CAST(order_date AS DATE)), 
       DATEPART(QUARTER, TRY_CAST(order_date AS DATE))
FROM ecommerce_staging
WHERE TRY_CAST(order_date AS DATE) IS NOT NULL;


--check for null values
SELECT COUNT(*) AS NullOrderDates
FROM ecommerce_staging
WHERE order_date IS NULL;

SELECT TOP 10 * FROM ecommerce_staging;

SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'ecommerce_staging' AND COLUMN_NAME = 'order_date';



--dim_locations table 
CREATE TABLE dim_locations (
    location_id INT PRIMARY KEY IDENTITY(1,1),
    customer_id NVARCHAR(50) UNIQUE,
    city NVARCHAR(100),
    state NVARCHAR(100),
    country NVARCHAR(100),
    FOREIGN KEY (customer_id) REFERENCES dim_customers(customer_id)
);

ALTER TABLE dim_locations 
ADD region NVARCHAR(100);


-- Insert data into fact_sales
--to check for duplicate order_id values
SELECT order_id, COUNT(*) AS OrderCount
FROM ecommerce_staging
GROUP BY order_id
HAVING COUNT(*) > 1;


drop table fact_sales
ALTER TABLE fact_sales 
ADD CONSTRAINT PK_fact_sales PRIMARY KEY (order_id, product_id);

SELECT e.order_id, e.product_id, COUNT(*)
FROM ecommerce_staging e
JOIN dim_dates d ON e.order_date = d.order_date
GROUP BY e.order_id, e.product_id
HAVING COUNT(*) > 1;



--insert data into fact_sales table 
INSERT INTO fact_sales (order_id, customer_id, product_id, salesperson_id, date_id, 
                        order_quantity, unit_price, total_price, discount, return_status)
SELECT e.order_id, 
       e.customer_id, 
       e.product_id, 
       e.salesperson_id, 
       MIN(d.date_id), 
       e.order_quantity, 
       e.unit_price, 
       e.total_price, 
       e.discount, 
       e.return_status
FROM ecommerce_staging e
JOIN dim_dates d ON e.order_date = d.order_date
WHERE NOT EXISTS (
    SELECT 1 
    FROM fact_sales f 
    WHERE f.order_id = e.order_id AND f.product_id = e.product_id
)
GROUP BY e.order_id, e.customer_id, e.product_id, e.salesperson_id, 
         e.order_quantity, e.unit_price, e.total_price, e.discount, e.return_status;


--remove unit_price column
ALTER TABLE fact_sales DROP COLUMN unit_price;

--verify the changes 
SELECT COLUMN_NAME 
FROM INFORMATION_SCHEMA.COLUMNS 
WHERE TABLE_NAME = 'fact_sales';

--Update Queries That Used unit_price
SELECT f.*, p.unit_price
FROM fact_sales f
JOIN dim_products p ON f.product_id = p.product_id;


--missing customer_id values 
SELECT DISTINCT e.customer_id 
FROM ecommerce_staging e
LEFT JOIN dim_customers c ON e.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

--add unknow to dim_customers
INSERT INTO dim_customers (customer_id, customer_name)  
VALUES ('Unknown', 'Unknown Customer');

--missing product_id values
SELECT DISTINCT e.product_id 
FROM ecommerce_staging e
LEFT JOIN dim_products p ON e.product_id = p.product_id
WHERE p.product_id IS NULL;

--Add Missing product_ids to dim_products
INSERT INTO dim_products (product_id, product_name, category, sub_category)  
SELECT DISTINCT e.product_id, 'Unknown Product', 'Unknown Category', 'Unknown Subcategory'
FROM ecommerce_staging e
LEFT JOIN dim_products p ON e.product_id = p.product_id
WHERE p.product_id IS NULL;


SELECT COLUMN_NAME, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'fact_sales' AND COLUMN_NAME IN ('order_id', 'product_id');

ALTER TABLE fact_sales 
ALTER COLUMN order_id NVARCHAR(50) NOT NULL;

ALTER TABLE fact_sales 
ALTER COLUMN product_id NVARCHAR(50) NOT NULL;


--to take the backup of the staging table 
SELECT * INTO backup_ecommerce_staging FROM ecommerce_staging;


--Create Final Cleaned Table
CREATE TABLE ecommerce_cleaned (
    order_id NVARCHAR(50) PRIMARY KEY,
    customer_id NVARCHAR(50),
    product_id NVARCHAR(50),
    salesperson_id NVARCHAR(50),
    date_id INT,
    order_quantity INT,
    total_price DECIMAL(12,2),
    discount DECIMAL(5,2),
    return_status VARCHAR(50),
    FOREIGN KEY (customer_id) REFERENCES dim_customers(customer_id),
    FOREIGN KEY (product_id) REFERENCES dim_products(product_id),
    FOREIGN KEY (salesperson_id) REFERENCES dim_salesperson(salesperson_id),
    FOREIGN KEY (date_id) REFERENCES dim_dates(date_id)
);

--insert data into ecommerce_cleaned
INSERT INTO ecommerce_cleaned
SELECT * FROM fact_sales;

select * from ecommerce_cleaned


--modifying ecommerce_cleaned
ALTER TABLE ecommerce_cleaned 
ADD city NVARCHAR(100), 
    state NVARCHAR(100), 
    country NVARCHAR(100);
alter TABLE ecommerce_cleaned 
ADD region NVARCHAR(100)
UPDATE e
SET e.city = l.city, 
    e.state = l.state, 
    e.country = l.country,
    e.region = l.region
FROM ecommerce_cleaned e
JOIN dim_locations l ON e.customer_id = l.customer_id;

ALTER TABLE ecommerce_cleaned
DROP COLUMN city, state, country, region;

SELECT * FROM ecommerce_cleaned WHERE city IS NULL OR state IS NULL OR country IS NULL OR region IS NULL;

--to check all Unknown customer entries
SELECT * FROM ecommerce_cleaned WHERE customer_id = 'Unknown';
select * from dim_customers

SELECT DISTINCT e.customer_id
FROM ecommerce_cleaned e
LEFT JOIN dim_locations l ON e.customer_id = l.customer_id
WHERE l.customer_id IS NULL;


INSERT INTO dim_locations (customer_id, city, state, country, region)
SELECT DISTINCT e.customer_id, 'Unknown', 'Unknown', 'Unknown', 'Unknown'
FROM ecommerce_cleaned e
LEFT JOIN dim_locations l ON e.customer_id = l.customer_id
WHERE l.customer_id IS NULL;



SELECT * FROM dim_locations WHERE city IS NULL OR state IS NULL OR country IS NULL OR region IS NULL;

--check if these IDs exist in ecommerce_staging
SELECT DISTINCT customer_id 
FROM ecommerce_staging 
WHERE customer_id NOT IN (SELECT customer_id FROM dim_customers);


--delete unknown customer_id entries
DELETE FROM ecommerce_cleaned WHERE customer_id = 'Unknown';

SELECT * FROM ecommerce_cleaned WHERE customer_id = 'Unknown';


------------------------

--to verify table structure of each each  
EXEC sp_help dim_customers;
EXEC sp_help dim_products;
EXEC sp_help dim_salesperson;
EXEC sp_help dim_dates;
EXEC sp_help fact_sales;



--Check Row Counts for Each Table
SELECT 'dim_customers' AS TableName, COUNT(*) AS Row_Count FROM dim_customers
UNION ALL
SELECT 'dim_products', COUNT(*) FROM dim_products
UNION ALL
SELECT 'dim_salesperson', COUNT(*) FROM dim_salesperson
UNION ALL
SELECT 'dim_dates', COUNT(*) FROM dim_dates
UNION ALL
SELECT 'fact_sales', COUNT(*) FROM fact_sales;



--Check for NULL values in Primary Keys
SELECT * FROM dim_customers WHERE customer_id IS NULL;
SELECT * FROM dim_products WHERE product_id IS NULL;
SELECT * FROM dim_salesperson WHERE salesperson_id IS NULL;
SELECT * FROM dim_dates WHERE date_id IS NULL;
SELECT * FROM fact_sales WHERE order_id IS NULL;



--Check for Orphaned Foreign Keys (Integrity Check)

SELECT f.customer_id FROM fact_sales f 
LEFT JOIN dim_customers d ON f.customer_id = d.customer_id 
WHERE d.customer_id IS NULL;

SELECT f.product_id FROM fact_sales f 
LEFT JOIN dim_products d ON f.product_id = d.product_id 
WHERE d.product_id IS NULL;

SELECT f.salesperson_id FROM fact_sales f 
LEFT JOIN dim_salesperson d ON f.salesperson_id = d.salesperson_id 
WHERE d.salesperson_id IS NULL;

SELECT f.date_id FROM fact_sales f 
LEFT JOIN dim_dates d ON f.date_id = d.date_id 
WHERE d.date_id IS NULL;



--Validate the fact_sales Data Mapping
SELECT f.order_id, f.date_id, d.order_date 
FROM fact_sales f
JOIN dim_dates d ON f.date_id = d.date_id
WHERE d.order_date IS NULL;



--Check for Duplicate Primary Keys
SELECT customer_id, COUNT(*) 
FROM dim_customers 
GROUP BY customer_id 
HAVING COUNT(*) > 1;

SELECT product_id, COUNT(*) 
FROM dim_products 
GROUP BY product_id 
HAVING COUNT(*) > 1;

SELECT salesperson_id, COUNT(*) 
FROM dim_salesperson 
GROUP BY salesperson_id 
HAVING COUNT(*) > 1;

SELECT date_id, COUNT(*) 
FROM dim_dates 
GROUP BY date_id 
HAVING COUNT(*) > 1;

SELECT order_id, COUNT(*) 
FROM fact_sales 
GROUP BY order_id 
HAVING COUNT(*) > 1;