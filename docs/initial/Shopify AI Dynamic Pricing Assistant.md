# **Shopify AI Dynamic Pricing Assistant** 

## **Introduction**

In this task, you will build a Shopify application that automatically adjusts product pricing based on inventory levels using AI.

The goal is to evaluate your ability in:

* Shopify Admin API integration  
* AI (Gemini) integration  
* Settings-driven business logic  
* Scheduled automation  
* Basic dashboard implementation

---

# **Problem Statement**

Create a Shopify application that automatically generates dynamic pricing recommendations using AI based on product inventory levels.

When stock decreases, the price should increase based on configurable rules defined by the merchant.

The system must:

* Fetch products from Shopify  
* Analyze inventory levels  
* Use Gemini AI to calculate recommended prices  
* Apply merchant-defined pricing rules  
* Display results in a dashboard

No manual approval flow is required. The system should directly update prices based on settings.

---

# 

# **Functional Requirements**

## **1\. Shopify Product Integration**

Your app must fetch products using Shopify Admin API.

Each product should include:

* Product Title  
* Product ID  
* Current Price  
* Inventory Quantity  
* Product Type  
* Vendor

Your system must also update product prices automatically.

---

## **2\. Settings Page**

Create a settings page where merchants define pricing rules.

### **A. Inventory Threshold**

Defines when dynamic pricing starts.

Example:

* Threshold \= 50  
* If stock \> 50 → no price change  
* If stock ≤ 50 → pricing logic is applied

---

### **B. Maximum Allowed Price**

Defines the highest price allowed for a product.

Example:

* Current Price \= $100  
* Maximum Price \= $150

AI must never generate a price higher than this value.

---

### **C. Review Frequency**

Defines how often the system runs pricing updates:

* Hourly  
* Daily  
* Weekly  
* Monthly

Your system must run automatically based on this setting.

---

### **D. AI Behavior Prompt (Optional)**

Allow merchants to define pricing behavior instructions.

Example:

"Be aggressive for premium products and conservative for low-cost items."

This should be included in the AI prompt sent to Gemini.

---

# **Validation Rules**

Your system must strictly enforce:

### **Rule 1**

Recommended price must NOT exceed the maximum allowed price.

### **Rule 2**

The recommended price must NOT be lower than the current price.

### **Rule 3**

Only products below or equal to the threshold should be processed.

### **Rule 4**

Invalid or malformed AI responses must be ignored safely.

---

# **Dashboard**

Create a simple dashboard that shows pricing updates.

### **Display:**

* Product Name  
* Current Inventory  
* Current Price  
* Recommended Price (AI generated)  
* AI Reason

The dashboard is read-only.

It is used to monitor system decisions.

---

# **Shopify Price Updates**

After AI generates a valid price:

* Automatically update product price in Shopify  
* Store updated values in your system database

---

# **Price History Tracking**

Maintain a list of all price changes.

Store:

* Product ID  
* Old Price  
* New Price  
* Inventory Level  
* Timestamp  
* AI Reason

Display the changes list in the dashboard.

---

# **Technical Requirements**

You may use any stack:

### **Backend:**

* Ruby on Rails

### **Frontend:**

* React  
* Shopify Polaris

### **Database:**

* PostgreSQL / MySQL / SQLite

### **AI:**

* Gemini API

### **Shopify:**

* Admin API

---

# **Deliverables**

Please submit:

1. GitHub repository link  
2. README with setup instructions  
3. Environment variables example file

### **Example `.env`**

SHOPIFY\_API\_KEY=  
SHOPIFY\_API\_SECRET=  
SHOPIFY\_ACCESS\_TOKEN=  
GEMINI\_API\_KEY=  
---

# 

# **References**

1. ### **Shopify Admin API Overview**

   [https://shopify.dev/docs/api/admin](https://shopify.dev/docs/api/admin)

2. ### **Shopify Product API (GraphQL)**

   [https://shopify.dev/docs/api/admin-graphql/latest/objects/product](https://shopify.dev/docs/api/admin-graphql/latest/objects/product)

3. ### **Gemini API Overview (Google AI Studio)**

   [https://ai.google.dev/gemini-api/docs](https://ai.google.dev/gemini-api/docs)

4. ### **Gemini API Quickstart**

   ### [https://ai.google.dev/gemini-api/docs/quickstart](https://ai.google.dev/gemini-api/docs/quickstart)

   

---

