# InsightEdge-Power-Bi-Dashboard
This project used raw retail sales data to build an interactive Power BI dashboard. It shows key sales insights across customers, products, discounts, regions, and salespeople. SQL was used to prepare the data, and Power BI (with DAX and smart UI elements) was used to design the final dashboard.


## **📁 Project Overview**
The InsightEdge project showcases a sales analytics dashboard that helps track and visualize:

- Net Revenue
- Orders & Profit Trends
- Customer Behavior
- Impact of Discounts
- Salesperson Contributions

It combines data modeling, transformation, and dashboard creation into a single streamlined workflow.


## **⚙️ Tools & Technologies Used**
| Tool | Purpose |
|-----------------|-----------------|
| SQL    | Data cleaning, transformation, and modeling   |
| Power BI    | Dashboard design, DAX-based KPIs & visuals    |
| DAX    | Custom measures and calculated metrics    |


## **🛠️ Data Preparation Workflow**
1. A staging table was created in SQL to load raw data.
2. Cleaning and transformation were performed:
    - Removed nulls and duplicates
    - Fixed data types and inconsistencies
3. A cleaned table was created for clean output.
4. A star schema model was built using cleaned tables.
5. Data was then loaded into Power BI, where:
    - DAX formulas were used to create KPIs
    - Pages were designed with slicers, buttons, and tooltips


## **📌 Dashboard Pages & Features**
 1. 🏠 Home Page
    - Net Revenue by Salesperson (Treemap)
    - Revenue vs Profit (Donut Chart)
    - Sales KPIs Table
    - Profit Comparison (Bar & Column Charts)
Quick overview of sales team performance and contribution.

2. 📈 Sales Analysis
    - Monthly Revenue and Profit Trends
    - Year-wise Category Revenue
    - Profit by Year with Discount Impact
    - KPI Cards: Revenue, Orders, AOV, Discount %
Analyze seasonal sales trends, category performance, and discount effects.

3. 🧑‍🤝‍🧑 Customer Insights
    - Customer-Wise Net Revenue & Order Count
    - Customer Category Analysis
    - Top vs Bottom Customers
Understand customer value, loyalty, and contribution to revenue.

4. 💸 Profits & Discounts
    - Discount vs Profit Visualizations
    - Year-wise Discount % Comparison
    - Sales with No Discount vs Discount Applied
Evaluate how discounts influence profits and sales quality.

5. 🧑‍💼 Salesperson Performance
    - Detailed Performance Table (Revenue, Profit, AOV)
    - Donut Chart for Revenue-Profit Ratio
    - Profit Leaderboard
Identify high and low-performing salespeople through multi-metric analysis.


## **🎛️ Global Filters & Navigation**
1. Slicers (on all pages):
    - Year
    - roduct Category
    - State
    - Region

2. Clear Filter Button:
    - Resets all slicers to show the unfiltered view.

3. Navigation Buttons:
    - Present on all pages (Home, Sales Analysis, Customer Insights, etc.)
    - Clickable for smooth transitions across pages


## ** 📌 Key Learnings **
- Practical experience with SQL for data preparation
- Implementing star schema for modeling
- Creating DAX measures like Net Revenue, Discount %, AOV, etc.
- Building interactive Power BI reports with a clean UI
- Using tooltips and info icons for guided navigation


## **📎 Note**
This project uses a random raw dataset (not real business data).
