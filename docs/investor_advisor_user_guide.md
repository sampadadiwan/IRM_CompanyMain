# Investor Advisor User Guide

This guide explains the **Investor Advisor** system in IRM, detailing how to set it up, how permissions are managed, and the specific capabilities and limitations of the advisor role.

---

## 1. Overview
An **Investor Advisor** is a third-party professional (e.g., from an advisory firm or family office) who is granted permissioned access to an entity's data. This allows them to manage or view funds, deals, and KYC documents on behalf of their clients without being a full employee of the client's entity.

The system uses a **Persona Switching** pattern, allowing the advisor to switch their active entity context from their "Home" advisory firm to the "Advised" client entity.

---

## 2. Setting Up an Investor Advisor

### Prerequisites
*   You must be a **Company Admin** or have appropriate permissions in the entity that wants to add an advisor.
*   The advisor's email address is required.

### Step-by-Step Setup
1.  **Navigate to the Source:** Go to the **Fund** or **Investor** page for which you want to add an advisor.
2.  **Initiate Addition:** Click on the **"Add Investor Advisor"** button (found in the "Team" or "Access" section).
3.  **Provide Details:**
    *   **Email:** The advisor's professional email.
    *   **First/Last Name:** The advisor's name.
    *   **Advisory Company Name:** The name of the advisor's firm.
4.  **System Processing:**
    *   If the user doesn't exist, the system creates a new **User** and a new **Entity** (of type "Investor Advisor") for them.
    *   An **InvestorAdvisor** record is created, linking the user to your entity.
    *   The system automatically grants **Access Rights** to the specific Fund and **Investor Access** to the specific Investor.
5.  **Notification:** The advisor will receive an email notification informing them they have been added as an advisor.

---

## 3. Permissions and Authorization (Technical Details)

The Investor Advisor's access is governed by a multi-layered permission system:

### A. The Advisor Role
*   The user is assigned the `:investor_advisor` role globally.
*   This role enables the **"Switch Persona"** feature in their user profile.

### B. Entity Switching (The "Switch" Mechanism)
*   When an advisor "switches" to your entity, their active `entity_id` changes to yours for that session.
*   **Role Transformation:** Their roles are temporarily replaced by the **Allowed Roles** defined during setup (default is `["investor"]`).
*   **Reversion:** When they switch back, their original `entity_id` and roles (e.g., `employee`, `investor_advisor`) are restored.

### C. Access Rights (Object-Level Security)
*   **Explicit Grant:** Advisors only see objects (Funds, Deals, etc.) for which they have an explicit `AccessRight` record.
*   **Metadata:** These records are tagged with `metadata: "investor_advisor"`. The system's `ApplicationPolicy` specifically checks for this metadata when validating advisor access.
*   **Investor Access:** They must also have an approved `InvestorAccess` record for the specific investor they are advising.

### D. Scopes and Filtering
*   The system uses specialized database scopes to ensure security:
    *   `InvestorKyc.for_investor_advisor(user)`: Filters KYCs to only those associated with funds the advisor has access to.
    *   `Fund.for_investor(user)`: Filters funds based on explicit access rights.

---

## 4. What an Advisor CAN Do
Once switched to the advised entity, an advisor can:
*   **View Permissioned Funds:** Access dashboards, reports, and documents for specific funds they manage.
*   **Manage KYC Documents:** View and (if permissioned) update KYC details for their clients.
*   **Track Investments:** Monitor capital commitments, remittances, and distributions for their permissioned investors.
*   **Receive Notifications:** Get alerts regarding KYC updates or fund activities related to their clients.

---

## 5. What an Advisor CANNOT Do
To maintain security and multi-tenancy, advisors are restricted from:
*   **Accessing Unpermissioned Data:** They cannot see any Funds, Investors, or Deals that haven't been explicitly shared with them.
*   **Administrative Actions:** They cannot manage your entity's settings, change employee permissions, or add other advisors.
*   **Global Entity Access:** They do not have the "Company Admin" view; they act as a restricted "Investor" or "Employee" within your entity.
*   **Cross-Client Visibility:** They cannot see data from other client entities they advise while switched into your entity's context.
