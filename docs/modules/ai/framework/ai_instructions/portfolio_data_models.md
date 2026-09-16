# Data Model Descriptions & Relationships: Portfolio Management

## 1. PortfolioInvestment
**Table Name:** `portfolio_investments`
**Purpose:** Represents an individual investment made by a fund into a portfolio company via a specific investment instrument. It tracks the quantity, cost, and computed fair market value (FMV) of the investment over time.

**Key Fields:**
- `investment_date` (date): The date the investment was made.
- `quantity` (decimal): The number of shares/units acquired.
- `amount_cents` (integer): The total amount invested.
- `tracking_amount_cents`, `tracking_fmv_cents` (integer): Amounts tracked in the fund's tracking currency.
- `ex_expenses_base_amount_cents`, `base_amount_cents`, `base_cost_cents` (integer): Costs in the instrument's base currency.
- `net_bought_amount_cents`, `net_amount_cents`, `cost_cents`, `fmv_cents`, `gain_cents`, `unrealized_gain_cents`, `cost_of_sold_cents`, `cost_of_remaining_cents` (integer): Various financial metrics computed and stored in the fund's primary currency.
- `portfolio_company_name` (string): Denormalized name of the portfolio company.
- `proforma` (boolean): Flag indicating if this is a proforma/scenario investment.

**Relationships:**
- **Belongs to Entity (`entity_id`):** Multi-tenant scope.
- **Belongs to Portfolio Company (`portfolio_company_id`):** The `Investor` record representing the startup.
- **Belongs to Investment Instrument (`investment_instrument_id`):** The specific security/instrument used.
- **Belongs to Fund (`fund_id`):** The fund making the investment.
- **Belongs to Aggregate Portfolio Investment (`aggregate_portfolio_investment_id`):** Link to the rolled-up view of this investment type.
- **Belongs to Capital Distribution (`capital_distribution_id`):** Link if the proceeds from selling this investment were distributed.
- **Belongs to Valuation (`valuation_id`):** The latest valuation applied to this investment for FMV calculation.
- **Has Many Valuations:** Through `investment_instrument`.
- **Has Many Portfolio Attributions (`sold_pi_id`, `bought_pi_id`):** Tracking of buys/sells and cost attribution.

---

## 2. Valuation
**Table Name:** `valuations`
**Purpose:** Stores the valuation of a specific investment instrument or an entire portfolio company at a given point in time. Used to calculate the Fair Market Value (FMV) of portfolio investments.

**Key Fields:**
- `valuation_date` (date): The effective date of the valuation.
- `per_share_value_cents` (integer): The calculated or provided value per single share/unit.
- `valuation_cents` (integer): Total valuation amount.
- `currency` (string): The currency of the valuation (e.g., USD, INR).
- `name` (string): Descriptive name, usually combining instrument/company and date.
- `synthetic` (boolean): Flag indicating if this valuation was system-generated vs manually entered.
- `meta_data` (json): Storage for custom fields and formula calculations.

**Relationships:**
- **Belongs to Entity (`entity_id`):** Multi-tenant scope.
- **Polymorphic Owner:** Uses `owner_type` and `owner_id` to link to the asset being valued (usually an `Investor` representing a portfolio company).
- **Belongs to Portfolio Company (`owner_id`):** A typed alias for when the owner is an `Investor`.
- **Belongs to Investment Instrument (`investment_instrument_id`):** The specific instrument this valuation applies to.

---

## 3. Investor
**Table Name:** `investors`
**Purpose:** The central model representing an external entity. It is heavily overloaded and can represent an LP (Limited Partner investing in a fund), a Portfolio Company (a startup receiving investment), or other business contacts.

**Key Fields:**
- `investor_name` (string): The legal or display name of the entity.
- `primary_email` (string): Primary contact address.
- `category` (string): Broad classification (e.g., "Individual", "Institution", "Portfolio Company").
- `pan` (string): Tax identification number.
- `city` (string): Location information.

**Relationships:**
- **Belongs to Entity (`entity_id`):** Multi-tenant scope.
- **Belongs to Investor Entity (`investor_entity_id`):** Link to the underlying `Entity` record representing this organization.
- **Has Many Kpi Reports (`portfolio_company_id`):** Performance reports when acting as a portfolio company.
- **Has Many Valuations (`owner_id`):** Valuations attached to this company.
- **Has Many Portfolio Investments (`portfolio_company_id`):** Investments made into this company.
- **Has Many Investment Instruments (`portfolio_company_id`):** Securities issued by this company.
- **Has Many Capital Commitments:** When acting as an LP.
- **Has Many Fund Units:** When acting as an LP.
- **Has Many Investor Accesses:** User login access mappings.
