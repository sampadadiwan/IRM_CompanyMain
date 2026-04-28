# InvestorAccess & AccessRight — Complete Tutorial

## Table of Contents

1. [Big Picture](#1-big-picture)
2. [InvestorAccess Module](#2-investoraccess-module)
3. [AccessRight Module](#3-accessright-module)
4. [Access Rights Cache](#4-access-rights-cache)
5. [How They Work Together](#5-how-they-work-together)
6. [Policy (Pundit) Authorization](#6-policy-pundit-authorization)
7. [UI & Routes](#7-ui--routes)
8. [Notifications](#8-notifications)
9. [Key File Locations](#9-key-file-locations)
10. [Investor Categories & Portfolio Companies](#10-investor-categories--portfolio-companies)

---

## 1. Big Picture

Caphive IRM serves two types of users from the same Rails app:

| | Fund Manager (FM) | Limited Partner (LP) |
|---|---|---|
| **Role** | `:employee` or `:company_admin` | `:investor` |
| **Entity type** | "Investment Fund", "Angel Fund", "Company" | "Investor", "Investment Advisor", "Family Office" |
| **Login** | Same `/users/sign_in` | Same `/users/sign_in` |
| **Sidebar** | Full admin sidebar | Restricted investor sidebar |
| **Data scope** | All entity data (company_admin) or granted records (employee) | Only data explicitly shared via AccessRights |

**Two modules control LP visibility:**

```
┌─────────────────────────────────────────────────────────┐
│  InvestorAccess                                          │
│  "WHO can log in and which Investor are they linked to?" │
│                                                          │
│  Links: User ↔ Investor ↔ Entity                        │
│  Gate:  approved = true/false                            │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│  AccessRight                                             │
│  "WHAT can they see once they're in?"                    │
│                                                          │
│  Grants: Fund, Document, Folder, Deal, KpiReport, etc.  │
│  Scope:  by investor_id, category, or user_id            │
│  Perms:  CRUD bitmask (create/read/update/destroy)       │
└─────────────────────────────────────────────────────────┘
```

**In plain English:**
- **InvestorAccess** = the door key (can this person get in?)
- **AccessRight** = the room keys (once in, what rooms can they enter?)

---

## 2. InvestorAccess Module

### What It Does

InvestorAccess is the bridge that links an LP **User** to an **Investor** record within a **Fund Entity**. Without an approved InvestorAccess, an LP user sees nothing.

### The Three-Way Link

```
Entity (Fund — e.g., "Fireside PE Fund I")
  │
  ├── Investor (LP record — e.g., "Acme Capital")
  │     │
  │     └── InvestorAccess (the link)
  │           │
  │           ├── user_id → User (the human — e.g., "John from Acme Capital")
  │           ├── investor_id → Investor (the LP record)
  │           ├── entity_id → Entity (the fund granting access)
  │           ├── investor_entity_id → Entity (the LP's own firm)
  │           ├── approved → boolean (the gate!)
  │           └── granted_by → User (who approved it)
  │
  └── (more investors...)
```

### Database Columns

| Column | Type | Purpose |
|--------|------|---------|
| `email` | string | LP user's email |
| `first_name` | string (max 20) | LP's first name |
| `last_name` | string (max 20) | LP's last name |
| `phone` | string (max 15) | Phone number |
| `cc` | text | CC email addresses (comma-separated) for notifications |
| `approved` | boolean (default: false) | **The gate** — controls all data visibility |
| `email_enabled` | boolean (default: true) | Whether to send email notifications |
| `whatsapp_enabled` | boolean (default: false) | WhatsApp notification toggle |
| `send_confirmation` | boolean (default: false) | Send confirmation email on user creation |
| `is_investor_advisor` | boolean (default: false) | Whether user is an investor advisor |
| `granted_by` | integer (FK → users) | User ID of the person who approved |
| `entity_id` | integer (FK → entities) | Fund entity granting access |
| `investor_id` | integer (FK → investors) | The investor (LP) record |
| `investor_entity_id` | bigint (FK → entities) | The LP's own entity/firm |
| `deleted_at` | timestamp | Soft delete (Paranoia gem) |
| `tags` | string (max 50) | Tags for grouping |

### Key Associations

```ruby
belongs_to :entity                    # The fund granting access
belongs_to :investor_entity           # The LP's firm (Entity)
belongs_to :investor                  # The LP investor record
belongs_to :user, touch: true         # The actual person logging in
belongs_to :granter, optional: true   # Who approved (User)
```

### Scopes

| Scope | SQL | Purpose |
|-------|-----|---------|
| `.approved` | `where(approved: true)` | Only approved accesses |
| `.unapproved` | `where(approved: false)` | Pending approvals |
| `.email_enabled` | `where(email_enabled: true)` | Will receive emails |
| `.investor_advisors` | `where(is_investor_advisor: true)` | Advisor users |
| `.approved_for_user(user)` | Complex — checks approved + entity match | All approved accesses for a specific user |
| `.approved_for(user, entity)` | Approved for user within specific entity | Scoped approval check |

### Approval Flow

```
Step 1: FM creates InvestorAccess (approved: false by default)
   │
   ▼
Step 2: FM reviews and clicks "Approve"
   │     → Sets approved = true
   │     → Sets granted_by = current_user.id
   │
   ▼
Step 3: After-commit callback fires
   │     → add_to_user_access_rights_cache
   │     → User's access_rights_cache is rebuilt
   │     → Notification email sent ("Access Granted to {entity_name}")
   │
   ▼
Step 4: LP user can now log in and see data
         (scoped by AccessRights — see next section)
```

**Unapproval flow:**
```
FM clicks "Unapprove"
  → approved = false
  → remove_from_user_access_rights_cache
  → LP user immediately loses all visibility
```

### Callbacks

| When | Callback | What It Does |
|------|----------|--------------|
| `before_validation` | `update_user` | Finds existing user by email or creates a new one. Sets `investor_entity_id`, assigns `:investor` role |
| `after_commit` | `add_to_user_access_rights_cache` | Rebuilds user's cached permissions when approved status changes |
| `after_destroy` | `remove_from_user_access_rights_cache` | Removes permissions from cache on deletion |

### Counter Culture (Denormalized Counts on Investor)

InvestorAccess maintains live counts on the parent Investor record:

| Counter Column on Investor | Condition |
|----------------------------|-----------|
| `investor_access_count` | `approved = true` |
| `unapproved_investor_access_count` | `approved = false` |
| `will_receive_email` | `approved = true AND email_enabled = true` |

### User Auto-Creation

When an FM creates an InvestorAccess, the `update_user` callback:

1. Strips whitespace from email
2. Looks for existing user by email
3. If **no user exists**: creates one with:
   - `entity_id` = investor's `investor_entity_id`
   - Auto-generated password
   - `system_created: true`
   - Optionally skips confirmation email (`skip_confirmation!`)
4. If **user exists**: reuses them
5. Sets `is_investor_advisor` based on user's cached role

---

## 3. AccessRight Module

### What It Does

AccessRight controls **what data** an LP can see. It's a polymorphic, bitmask-based permission system that grants access to specific resources (Funds, Documents, Folders, Deals, etc.).

### The Three Grant Paths

An AccessRight can target recipients via three mutually exclusive paths:

```
AccessRight
  │
  ├── Path 1: access_to_investor_id  →  Specific investor (e.g., "Acme Capital")
  │     All approved users of this investor get access
  │
  ├── Path 2: access_to_category     →  Investor category (e.g., "Portfolio Company")
  │     All investors in this category (and their users) get access
  │
  └── Path 3: user_id               →  Specific user (e.g., employee or advisor)
        Only this one user gets access
```

### Database Columns

| Column | Type | Purpose |
|--------|------|---------|
| `owner_id` | integer | The resource being shared (polymorphic) |
| `owner_type` | string | Type of resource: "Fund", "Document", "Folder", "Deal", etc. |
| `entity_id` | integer (FK) | Entity granting access |
| `access_to_investor_id` | integer (FK) | Grant to specific investor |
| `access_to_category` | string (max 20) | Grant to all investors of a category |
| `user_id` | integer (FK) | Grant to specific user |
| `permissions` | integer (bitmask) | CRUD permissions (create=1, read=2, update=4, destroy=8) |
| `metadata` | string | Extra context (e.g., "Buyer", "Seller", "RM") |
| `access_type` | string (max 25) | Type label for UI |
| `notify` | boolean | Whether to notify recipients |
| `granted_by` | integer (FK) | User who created this right |
| `parent_access_right_id` | integer (FK) | For inherited/cascaded rights (folder → child docs) |
| `deleted_at` | timestamp | Soft delete |

### Polymorphic Owner — What Can Be Shared

| Owner Type | Example |
|------------|---------|
| `Fund` | "Fireside PE Fund I" — LP can see fund details |
| `Document` | "Q4 Valuation Report" — LP can download this doc |
| `Folder` | "Investor Reports" folder — LP sees all docs inside |
| `Deal` | "Series B — Acme Corp" — LP can view deal details |
| `InvestmentOpportunity` | Co-investment opportunity |
| `SecondarySale` | Secondary market deal |
| `KpiReport` | KPI reporting period |
| `Approval` | Approval request |
| `Nudge` | Notification nudge |

### Permission Bitmask

```ruby
# Bitmask values
create  = 1   # 0001
read    = 2   # 0010
update  = 4   # 0100
destroy = 8   # 1000

# Examples:
permissions = 2       # read only
permissions = 7       # create + read + update (1+2+4)
permissions = 15      # full CRUD (1+2+4+8)
```

### Metadata Field

The metadata field adds conditional logic to access:

| Context | Metadata Value | Meaning |
|---------|---------------|---------|
| SecondarySale | `"Buyer"` | LP is on the buy side |
| SecondarySale | `"Seller"` | LP is on the sell side |
| RM mapping | `"RM"` | User is a Relationship Manager |
| General | `nil` or `""` | No special condition |

### Key Scopes

| Scope | Purpose |
|-------|---------|
| `.for(owner)` | Rights for a specific resource |
| `.for_user(user_id)` | Rights granted to specific user |
| `.for_investor(investor)` | Rights for an investor (by ID or category) |
| `.access_filter(user)` | **Main filter** — contextual based on user's role |
| `.investor_access(investor, user)` | Combined check: investor + user + category |

### `access_filter` — The Core Scoping Logic

```ruby
def self.access_filter(user)
  if user.investor_advisor?  # Currently switched into an investor
    # Only show rights granted directly to user OR to the specific investor
    where("access_rights.user_id = ? OR access_rights.access_to_investor_id = investors.id", user.id)

  elsif user.has_cached_role?(:investor_advisor) && !user.investor_advisor?
    # IA with role but viewing as their original entity
    where("investors.category = access_rights.access_to_category OR ...")

  else
    # Regular employee/investor — check all three paths
    where("investors.category = access_rights.access_to_category
           OR access_rights.access_to_investor_id = investors.id
           OR access_rights.user_id = ?", user.id)
  end
end
```

### Cascade: Folder → Child Documents

When an AccessRight is created on a **Folder**, it cascades down:

```
Folder "Investor Reports"  ← AccessRight created here
  │
  ├── Document "Q1 Report.pdf"  ← AccessRight auto-replicated
  ├── Document "Q2 Report.pdf"  ← AccessRight auto-replicated
  └── Subfolder "2025"          ← AccessRight auto-replicated
        └── Document "Annual.pdf"  ← AccessRight auto-replicated
```

This is done via:
- `replicate_to(new_owner)` method — creates child AccessRight linked via `parent_access_right_id`
- `AccessRightsDeletedJob` — on deletion, cascades removal through the hierarchy

### Callbacks

| When | Callback | What It Does |
|------|----------|--------------|
| `after_create_commit` | `send_notification` | Notifies recipient users via AccessRightNotifier |
| `after_commit` | `add_to_user_access_rights_cache` | Caches right in each recipient user's cache |
| `after_destroy_commit` | `remove_from_user_access_rights_cache` | Removes from cache |
| `after_destroy_commit` | `AccessRightsDeletedJob` | Cascades deletion through folder/doc hierarchy |

### Validations

- **`access_is_unique`**: No duplicate rights (same owner + target + entity)
- **`any_present?`**: At least one target must be set (`access_to_investor_id`, `access_to_category`, or `user_id`)
- Length limits on `access_type` (25) and `access_to_category` (20)

---

## 4. Access Rights Cache

### Why a Cache?

Checking AccessRights via database joins on every page load would be expensive. Instead, Caphive denormalizes each user's permissions into a cached hash stored on the User model.

**File:** `app/packs/core/users/models/concerns/access_rights_cache.rb`

### Cache Structure

```ruby
# User#access_rights_cache (serialized Hash)
{
  entity_id => {
    owner_type => {
      owner_id => "permissions_bitmask,metadata"
    }
  }
}

# Real example:
{
  157 => {
    "Fund" => {
      5 => "7,",        # Fund #5: create+read+update, no metadata
      12 => "2,"        # Fund #12: read only
    },
    "Document" => {
      42 => "2,",       # Document #42: read only
      99 => "4,Buyer"   # Document #99: update, metadata="Buyer"
    }
  }
}
```

### When Is the Cache Rebuilt?

| Event | What Happens |
|-------|-------------|
| InvestorAccess approved | `refresh_access_rights_cache(investor_access, add: true)` |
| InvestorAccess unapproved/deleted | `refresh_access_rights_cache(investor_access, add: false)` |
| AccessRight created | `cache_access_rights(access_right)` for each target user |
| AccessRight deleted | `remove_access_rights_cache(access_right)` for each target user |
| Role change | `reset_access_rights_cache` — full rebuild |
| Manual reset | `PATCH /users/:id/reset_access_rights_cache` |

### Key Methods

| Method | Purpose |
|--------|---------|
| `cache_access_rights(ar)` | Add a single AccessRight to cache |
| `remove_access_rights_cache(ar)` | Remove a single AccessRight from cache |
| `reset_access_rights_cache` | Full rebuild from database |
| `refresh_access_rights_cache(ia, add:)` | Targeted rebuild for an InvestorAccess change |
| `get_cached_access_rights_permissions(entity_id, type, id)` | Returns `[permissions, metadata]` |
| `get_cached_ids(entity_id, owner_type)` | Returns all owner IDs user has access to |

### Cache Population by Role

| User Role | Cache Source |
|-----------|-------------|
| Company Admin | **No cache needed** — sees everything in their entity |
| Employee | `AccessRight.where(user_id: user.id)` |
| Investor (LP) | `AccessRight` matching their `investor_id` or `category` |
| Investor Advisor | Accumulated rights across all investor entities they advise |

---

## 5. How They Work Together

### End-to-End Flow: FM Shares a Fund with an LP

```
Step 1: FM Creates Investor Record
   FM adds "Acme Capital" as an Investor in their fund entity
   → Investor record created (entity_id = fund's entity)

Step 2: FM Creates InvestorAccess
   FM adds John (john@acme.com) as a stakeholder for Acme Capital
   → InvestorAccess created (approved: false by default)
   → User auto-created for john@acme.com (role: :investor)
   → User's entity = Acme Capital's investor_entity

Step 3: FM Approves InvestorAccess
   FM clicks "Approve" on John's access
   → approved = true, granted_by = FM's user ID
   → Notification email: "Access Granted to {fund_name}"
   → User's access_rights_cache is rebuilt (but empty — no AccessRights yet)

Step 4: FM Creates AccessRight on Fund
   FM shares "Growth Fund" with category "All Investors" or specific investor
   → AccessRight created:
       owner_type: "Fund", owner_id: growth_fund.id
       access_to_category: "Investor" (or access_to_investor_id: acme.id)
       permissions: 2 (read only)
   → Cache updated for all matching approved users (including John)

Step 5: FM Shares Documents
   FM shares a Folder "Investor Reports" with Acme Capital
   → AccessRight created on Folder
   → Cascades to all Documents inside the folder
   → John's cache now includes Fund + Folder + Documents

Step 6: LP Logs In
   John logs in at /users/sign_in with john@acme.com
   → Sees investor sidebar (not FM sidebar)
   → Pundit policies check access_rights_cache
   → John sees: Growth Fund, Investor Reports folder, documents inside
   → John does NOT see: other funds, other investors' docs, admin features
```

### Visual Flow

```
FM Action                          System                           LP Experience
─────────                          ──────                           ─────────────
Create Investor ─────────────────→ Investor record created
                                                                    
Create InvestorAccess ───────────→ User auto-created                LP can log in
                                   (approved: false)                (but sees nothing)
                                                                    
Approve InvestorAccess ──────────→ approved = true                  LP sees empty
                                   Cache rebuilt (empty)            dashboard
                                   Email sent                       
                                                                    
Create AccessRight on Fund ──────→ Cache updated                    LP sees Fund
                                   Notification sent                details
                                                                    
Share Folder with LP ────────────→ AccessRight cascades             LP sees folder
                                   to child documents               + all docs inside
                                                                    
Unapprove InvestorAccess ────────→ approved = false                 LP sees nothing
                                   Cache cleared                    (immediate)
```

---

## 6. Policy (Pundit) Authorization

### How Policies Check Permissions

Every controller action calls Pundit. Policies use the access_rights_cache for fast lookups.

**File:** `app/packs/core/base/policies/application_policy.rb`

### Four Permission Check Methods

#### 1. `permissioned_employee?(perm, owner:)`
- **Who:** Users belonging to the same entity as the record
- **Company admins:** Always true (see everything)
- **Employees:** Checks `access_rights_cache` for the specific owner
- **Example:** Employee can only see Funds they've been explicitly granted

#### 2. `permissioned_investor_non_advisor?(metadata, owner:)`
- **Who:** `curr_role == 'investor'` AND does NOT belong to entity
- **How:** Looks up cached permissions for investor's entity
- **Metadata check:** Validates optional metadata (e.g., only "Buyer")
- **Example:** LP sees Fund details shared with their investor category

#### 3. `permissioned_investor_advisor?(metadata, owner:, as_entity_id:)`
- **Who:** Users with cached role `:investor_advisor`
- **How:** Searches cache with specific `as_entity_id`
- **Example:** Advisor logged in as LP Entity A sees Funds shared with that entity

#### 4. `permissioned_rm?(metadata, owner:)`
- **Who:** Users with cached role `:rm`
- **How:** Checks cache + validates rm_mappings exist
- **Example:** RM only sees Deals they're mapped to manage

### Permission Inheritance

Child records inherit permissions from parents:

```
Fund (AccessRight exists)
  └── Commitment (no direct AccessRight needed)
        → Policy checks Fund-level rights via get_model_with_access_rights
        → LP can see Commitment because they have Fund access

Folder (AccessRight exists)
  └── Document (AccessRight auto-cascaded)
        → Direct AccessRight exists (replicated from Folder)
```

The `get_model_with_access_rights` helper maps child → parent:

| Child Model | Checks Parent |
|-------------|---------------|
| Commitment | → Fund |
| CapitalCall | → Fund |
| Distribution | → Fund |
| Offer | → SecondarySale |
| Interest | → SecondarySale |
| DealInvestor | → Deal |

---

## 7. UI & Routes

### InvestorAccess Routes

```
GET    /investor_accesses                    # List all
POST   /investor_accesses                    # Create new
GET    /investor_accesses/new                # New form
GET    /investor_accesses/:id                # Show details
GET    /investor_accesses/:id/edit           # Edit form
PATCH  /investor_accesses/:id                # Update
DELETE /investor_accesses/:id                # Soft delete
PATCH  /investor_accesses/:id/approve        # Toggle approval
POST   /investor_accesses/request_access     # LP requests access
POST   /investor_accesses/upload             # Bulk import
GET    /investor_accesses/search             # Elasticsearch search
```

### AccessRight Routes

```
GET    /access_rights                        # List all
POST   /access_rights                        # Create new
GET    /access_rights/:id/edit               # Edit form
PATCH  /access_rights/:id                    # Update
DELETE /access_rights/:id                    # Soft delete
```

### LP Sidebar

When an LP logs in, they see this sidebar (`_sidebar_investor.html.erb`):

```
- Investments          (if enable_investments flag)
- Deals                (if enable_deals flag)
- Offers & Interests   (if enable_secondary_sale flag)
- Approvals            (if enable_approvals flag)
```

### AccessRight Form — How FM Grants Access

The FM sees a form with:

1. **Access Type selection** — radio buttons:
   - "All Stakeholders of Specific Category"
   - "All Users for Specific Stakeholder"
   - "Specific User"

2. **Category multi-select** — if granting by category (e.g., "Portfolio Company", "Investor")

3. **Investor multi-select** — if granting to specific investors

4. **User multi-select** — if granting to specific users/employees

5. **Permissions checkboxes** — Create / Read / Update / Destroy

6. **Metadata field** — for SecondarySale (Buyer/Seller)

7. **Notify checkbox** — whether to email recipients

---

## 8. Notifications

### InvestorAccess Notifications

| Event | Notification | Channel |
|-------|-------------|---------|
| Access approved | "Access Granted to {entity_name}" | Email via InvestorAccessNotifier |
| Email includes | Login link with pre-filled email | |

### AccessRight Notifications

| Event | Notification | Channel |
|-------|-------------|---------|
| New access right created (if notify=true) | "You have been granted access to {resource}" | Email via AccessRightNotifier |
| Recipients | All approved users of the target investor | |

### Notification Flow

```
AccessRight created (notify: true)
  → after_create_commit :send_notification
  → investor.notification_users(owner) — gets approved users
  → For each user: AccessRightNotifier.deliver_later(user)
  → Email sent via AccessRightsMailer
```

---

## 9. Key File Locations

### InvestorAccess

| Component | Path |
|-----------|------|
| Model | `app/packs/core/investor_accesses/models/investor_access.rb` |
| Controller | `app/packs/core/investor_accesses/controllers/investor_accesses_controller.rb` |
| Policy | `app/packs/core/investor_accesses/policies/investor_access_policy.rb` |
| Mailer | `app/packs/core/investor_accesses/mailers/investor_access_mailer.rb` |
| Notifier | `app/packs/core/investor_accesses/mailers/investor_access_notifier.rb` |
| Views | `app/packs/core/investor_accesses/views/investor_accesses/` |
| Search Index | `app/packs/core/investor_accesses/models/investor_access_index.rb` |
| Services | `app/packs/core/investor_accesses/services/` |

### AccessRight

| Component | Path |
|-----------|------|
| Model | `app/packs/core/access_rights/models/access_right.rb` |
| Controller | `app/packs/core/access_rights/controllers/access_rights_controller.rb` |
| Policy | `app/packs/core/access_rights/policies/access_right_policy.rb` |
| Mailer | `app/packs/core/access_rights/mailers/access_rights_mailer.rb` |
| Notifier | `app/packs/core/access_rights/mailers/access_right_notifier.rb` |
| Helper | `app/packs/core/access_rights/helpers/access_rights_helper.rb` |
| Views | `app/packs/core/access_rights/views/access_rights/` |
| Search Index | `app/packs/core/access_rights/models/access_right_index.rb` |
| Cascade Job | `app/packs/core/access_rights/jobs/access_rights_deleted_job.rb` |

### Shared / Cross-Cutting

| Component | Path |
|-----------|------|
| Access Rights Cache | `app/packs/core/users/models/concerns/access_rights_cache.rb` |
| ForInvestor Concern | `app/packs/core/investors/models/concerns/for_investor.rb` |
| ApplicationPolicy | `app/packs/core/base/policies/application_policy.rb` |
| User Model | `app/packs/core/users/models/user.rb` |
| Investor Model | `app/packs/core/investors/models/investor.rb` |

---

## 10. Investor Categories & Portfolio Companies

### Investor Categories

The `Investor` model has a `category` field. Categories are configured via:
- **Dynamic:** `ENV["INVESTOR_CATEGORIES"]` environment variable
- **Always added:** "Prospective"
- **Fund-only:** "Portfolio Company" (added dynamically when entity type is "Investment Fund" or "Angel Fund")
- **Other common categories:** "Investor Advisor", "RM", "Wealth Manager"

### Can Portfolio Company Contacts Log In?

**Yes.** Portfolio company representatives (e.g., a portco CFO) use the exact same InvestorAccess + AccessRight mechanism as LPs. There is no separate login flow or portal.

```
FM creates Investor record (category = "Portfolio Company")
  → FM adds portco contact as InvestorAccess (email, name)
  → User auto-created with :investor role
  → FM approves → contact can log in
  → FM grants AccessRights → contact sees specific data
```

### What Does a Portfolio Company User See?

**Same investor sidebar as an LP** — no special portco sidebar:
- Investments (if `enable_investments`)
- Deals (if `enable_deals`)
- Offers & Interests (if `enable_secondary_sale`)
- Approvals (if `enable_approvals`)

They see whatever the FM has shared with them via AccessRights (documents, fund details, etc.).

### How Are Portcos Different from Regular Investors? (Backend)

The differences are in the **data model**, not in the login/UI experience:

| Feature | Portfolio Company | Regular Investor (LP) |
|---------|-------------------|----------------------|
| Sector field | Yes (cleared if category changes) | No |
| KPI reports | Has portco KPI relationships | No |
| Cap table | Special policy: category must be "Portfolio Company" | No |
| Valuations | Triggers portfolio investment recalculations | No |
| Dashboard label | "Portfolio Company Dashboard" | "Investor Dashboard" |
| Portfolio investments | Buy/sell transactions, instruments, cashflows | No |
| Stock adjustments/conversions | Yes | No |

### Category-Based Access Grants

AccessRights can be granted by category, which means:

```
AccessRight: owner = Fund, access_to_category = "Portfolio Company"
  → ALL investors with category "Portfolio Company" get access
  → All their approved InvestorAccess users can see this Fund
```

This is different from:

```
AccessRight: owner = Fund, access_to_category = "Investor"
  → Only investors with category "Investor" (regular LPs) get access
  → Portfolio Company users do NOT get access from this grant
```

Categories are **strict matches** — an AccessRight targeting "Investor" does not apply to "Portfolio Company" users, and vice versa.

---

## Quick Reference: Common Scenarios

### "I want to give an LP access to a fund"

1. Ensure Investor record exists for the LP firm
2. Create InvestorAccess linking user → investor → entity (approve it)
3. Create AccessRight: `owner = Fund, access_to_investor_id = investor.id, permissions = 2 (read)`

### "I want to share a document with all LPs"

1. Create AccessRight: `owner = Document, access_to_category = "Investor", permissions = 2`
2. All approved InvestorAccess users in that category get access

### "An LP says they can't see anything"

Check in order:
1. Does User have role `:investor`?
2. Does InvestorAccess exist? Is `approved = true`?
3. Do AccessRights exist for the resources? (Check `access_to_investor_id` or `access_to_category`)
4. Is the user's `access_rights_cache` populated? (Try manual reset: `PATCH /users/:id/reset_access_rights_cache`)

### "I want to revoke LP access"

Option A: Unapprove InvestorAccess → LP loses ALL access instantly
Option B: Delete specific AccessRights → LP loses access to those resources only
