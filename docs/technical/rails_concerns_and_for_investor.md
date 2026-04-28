# Rails Concerns, Callbacks, and `ForInvestor` — Deep Dive

This document explains:

1. **Ruby/Rails fundamentals** — modules, concerns, callbacks, scopes, class vs instance methods
2. **Line-by-line walkthrough** of `app/packs/core/investors/models/concerns/for_investor.rb`
3. **How it flows at LP login** — and why the same code handles Funds, CapitalCommitments, PortfolioInvestments, etc.

Audience: someone who writes Ruby and wants a precise mental model of how this concern works under the hood.

---

## Part 1 — Ruby/Rails Fundamentals

### 1.1 Classes vs Modules

In Ruby, a **class** is a template for objects. A class can have only one parent. A **module** is a bag of methods / constants — it cannot be instantiated, but it can be *mixed into* any class.

```ruby
class Fund < ApplicationRecord   # single-inheritance
end

module Billable
  def charge(amount)
    ...
  end
end

class Fund < ApplicationRecord
  include Billable        # mix Billable's methods into Fund
end

Fund.new.charge(100)      # works — Fund now has #charge
```

Why not just use inheritance? Because `Fund` already inherits from `ApplicationRecord`, and Ruby doesn't allow two parents. Modules let us share behaviour *horizontally* across many unrelated models — exactly the problem `ForInvestor` solves for Fund, CapitalCommitment, Offer, Kpi, etc.

### 1.2 What a Rails "concern" actually is

A **concern** is a module that uses `ActiveSupport::Concern` to tidy up the boilerplate involved in mixing class-level setup (scopes, callbacks, associations) into another class.

Without `ActiveSupport::Concern` you'd write:

```ruby
module ForInvestor
  def self.included(base)
    base.scope :for_investor, ->(user) { ... }
  end
end
```

With it:

```ruby
module ForInvestor
  extend ActiveSupport::Concern

  included do                    # runs in context of the including class
    scope :for_investor, ->(user) { ... }
  end

  class_methods do               # defines class-level methods
    def some_class_method
      ...
    end
  end

  def some_instance_method       # becomes an instance method
    ...
  end
end
```

**Three slots** in a concern:

| Slot | What happens | Becomes |
|---|---|---|
| `included do ... end` | Runs **when** a class does `include ForInvestor`, in the including class's context. | Scopes, callbacks, associations, validations on the class. |
| `class_methods do ... end` | Defines class-level methods. | Methods callable on the class: `Fund.some_method`. |
| Plain `def foo` at module top level | Normal module method. | **Instance** methods on the including class: `fund.foo`. |

### 1.3 Class methods vs Instance methods

- **Class method** — called on the class itself: `Fund.for_investor(user)`. Receiver is the class object.
- **Instance method** — called on a specific record: `commitment.model_with_access_rights`. Receiver is an instance.

Scopes (see §1.5) are technically class methods. `def self.X`, `class_methods do ... end`, and `scope :x` all ultimately produce class methods on the including class.

### 1.4 `include` vs `extend`

- `include SomeModule` — adds the module's methods as **instance** methods.
- `extend SomeModule` — adds the module's methods as **class** methods.

That's why `ForInvestor` says `extend ActiveSupport::Concern` at the top — `ActiveSupport::Concern` provides class-level helpers (`included`, `class_methods`) that must be available on the module being defined.

### 1.5 Scopes

A **scope** is sugar for defining a class method that returns an `ActiveRecord::Relation` — a chainable query.

```ruby
class Fund < ApplicationRecord
  scope :active,    -> { where(active: true) }
  scope :in_entity, ->(eid) { where(entity_id: eid) }
end

Fund.active.in_entity(157).limit(10)
# => a chain of Relations; one SQL query fires on .to_a / iteration
```

Equivalent to:

```ruby
def self.active
  where(active: true)
end
```

A scope with arguments is just a class method that takes arguments. The key property is **composability**: `Fund.active.in_entity(157).where(name: 'Growth').limit(10)` chains into a single SQL query.

### 1.6 Callbacks

Callbacks hook behaviour onto a record's lifecycle:

```ruby
class AccessRight < ApplicationRecord
  after_commit :update_owner
end
```

When `AccessRight.create!` succeeds and the DB transaction commits, Rails runs `update_owner`. That's what fired Chewy's reindex when you seeded the grant — the callback tried to update the search index.

`ForInvestor` doesn't register callbacks, but many other concerns do. Common ones:
- `after_commit`, `after_create`, `after_save`
- `before_validation`, `before_save`
- `around_save`, `around_destroy`

### 1.7 `lambda`, `->`, `Proc`

`lambda { |x| ... }` and `->(x) { ... }` produce the same thing: a `Proc` with **strict arity** (passing the wrong number of arguments raises). `scope :name, ->(a, b) { ... }` stores the lambda and invokes it when you call `Model.name(a, b)`.

### 1.8 Runtime reflection

Methods like `method_defined?(:access_rights)`, `respond_to?(:user_id)`, `name.underscore.pluralize` ask at runtime "does this class have this method / association?" and branch accordingly. That's how one concern serves multiple models with different schemas from a single definition.

---

## Part 2 — Line-by-line Walkthrough of `for_investor.rb`

File: [app/packs/core/investors/models/concerns/for_investor.rb](../../app/packs/core/investors/models/concerns/for_investor.rb)

---

### Opening

```ruby
module ForInvestor
  extend ActiveSupport::Concern
```

Declares the module and opts into the Concern DSL so `included do` and `class_methods do` are available.

---

```ruby
  included do
```

Everything in this block runs **when a class includes `ForInvestor`**, in that class's context. `scope` and `def self.X` defined here get attached to the including class.

---

### Class method: `parent_class_type`

```ruby
def self.parent_class_type
  if %w[CapitalCommitment CapitalRemittance ... RatioFormula].include?(name)
    Fund
  elsif ["ExpressionOfInterest"].include?(name)
    InvestmentOpportunity
  elsif %w[Offer Interest Allocation].include?(name)
    SecondarySale
  elsif %w[Kpi].include?(name)
    KpiReport
  elsif %w[DealInvestor].include?(name)
    Deal
  else
    self
  end
end
```

**Technical:** returns the class that *owns the access-rights rows* for the including model. `name` here is the including class's name (e.g. `"Fund"`, `"CapitalCommitment"`).

**Functional:**
- Not every model has its own `access_rights`. Many borrow from a parent.
- A `CapitalCommitment` has no access_rights row of its own — visibility is decided by the **Fund** it belongs to → `CapitalCommitment.parent_class_type == Fund`.
- A `Fund` owns its own access_rights → `Fund.parent_class_type == Fund` (the `else self` branch).
- Secondary market models borrow from `SecondarySale`; `Kpi` borrows from `KpiReport`; etc.

Downstream scopes call this to figure out which table/association to join on.

---

### Scope: `for_company_admin`

```ruby
scope :for_company_admin, lambda { |user|
  table_name = parent_class_type.name.underscore.pluralize
  join_clause = if parent_class_type.name == name
                  joins(:entity)
                else
                  joins(parent_class_type.name.underscore.to_sym)
                end

  if user.entity_type == "Group Company"
    join_clause.where("#{table_name}": { entity_id: user.entity.child_ids })
  else
    join_clause.where("#{table_name}": { entity_id: user.entity_id })
  end
}
```

**Technical:**
- `parent_class_type.name.underscore.pluralize` → `"funds"` (for models whose parent is Fund).
- If the model IS the parent (`Fund.parent_class_type == Fund`), join directly to `:entity`. Otherwise join to the parent association (e.g. `joins(:fund)`).
- Filter by entity_id. For a "Group Company" user (parent entity with subsidiaries), include all child entity ids.

**Functional:** "Show me all rows where the owning Fund (or owning parent record) belongs to an entity that this company admin manages." Used when a **Fund Manager admin** loads dashboards.

---

### Scope: `for_employee`

```ruby
scope :for_employee, lambda { |user|
  ...
  cached_ids = user.get_cached_ids(user.entity_id, parent_class_type.name)
  ...
  join_clause.where("#{table_name}": { entity_id: ..., id: cached_ids })
}
```

**Technical:** Same entity filter as `for_company_admin`, PLUS restrict to specific record IDs the employee was granted. `get_cached_ids` hits `AccessRightCache` — a denormalised lookup precomputed for speed.

**Functional:** A regular FM employee (not admin) only sees specific funds/portfolios their manager granted them. Without caching this would be an expensive join every request.

---

### Scope: `for_rm` (Relationship Manager)

```ruby
scope :for_rm, lambda { |user|
  join_clause = if method_defined?(:access_rights)
                  if method_defined?(:investor)
                    joins(:access_rights).joins(investor: :rm_mappings)
                  else
                    joins(:access_rights).joins(entity: :investors)
                  end
                elsif method_defined?(:investor)
                  joins(investor: :rm_mappings).joins(parent_class_type.name.underscore => :access_rights)
                else
                  joins(parent_class_type.name.underscore => :access_rights).joins(entity: :investors)
                end
  ...
}
```

**Technical:** Four-way branch based on runtime reflection:

| Model has... | Join shape |
|---|---|
| `access_rights` + `investor` | `joins(:access_rights).joins(investor: :rm_mappings)` |
| `access_rights` only | `joins(:access_rights).joins(entity: :investors)` |
| `investor` only | `joins(investor: :rm_mappings).joins(parent => :access_rights)` |
| Neither | `joins(parent => :access_rights).joins(entity: :investors)` |

Then applies `AccessRight.access_filter_for_rm(user)` (for models with an investor) or `AccessRight.access_filter(user)` (for models without), restricted to `rm_mappings.rm_entity_id = user.entity_id`.

**Functional:** Relationship Managers are FM-side humans assigned to manage specific investors. This scope returns rows whose investor is in the RM's assignment list. The filtering combines access-rights + rm_mappings: a row is visible if the RM is mapped to that investor AND the investor has an access grant.

The final lines:

```ruby
join_clause = join_clause.joins(entity: :investor_accesses).merge(InvestorAccess.approved_for_user(user))
join_clause = join_clause.where("#{self.table_name}.user_id" => user.id) if respond_to?(:user_id) && !user.has_cached_role?(:company_admin)
```

- Require `InvestorAccess.approved = true` (investor has accepted the FM's invite).
- If the model itself has a `user_id` column and the RM isn't a company_admin, further restrict to rows owned by this user.

---

### Scope: `for_investor` (the one LP Assistant uses)

```ruby
scope :for_investor, lambda { |user, across_all_entities: false|
  raise "across_all_entities should not be true for non investor_advisor users" if across_all_entities && !user.has_cached_role?(:investor_advisor)
```

**`across_all_entities` guard.** Investor advisors manage multiple investor entities. When an advisor is logged in *as an investor* but performing actions that span all their clients (e.g. sending email), we need funds across ALL advised investors. This is a special case — regular LPs never pass `across_all_entities: true`. The `raise` enforces that invariant.

---

```ruby
  filter = if user.investor_advisor? || (across_all_entities && user.has_cached_role?(:investor_advisor))
             AccessRight.investor_granted_access_filter(user, across_all_entities:)
           else
             across_all_entities = false
             AccessRight.access_filter(user)
           end
```

**Pick the access-rights filter:**
- **Investor advisor path** → special filter that considers all entities they advise.
- **Regular LP path** → `AccessRight.access_filter(user)` — matches access_rights where `access_to_category` equals the investor's category, or `access_to_investor_id` equals the investor's id, or `user_id` equals this user's id (direct grant).

The `filter` is an `ActiveRecord::Relation` on `AccessRight` that we'll `.merge` in later.

---

```ruby
  join_clause = if method_defined?(:access_rights)
                  Rails.logger.debug { "######## for_investor has access_rights" }
                  if method_defined?(:investor)
                    Rails.logger.debug { "######## for_investor has :investor" }
                    joins(:access_rights).joins(:investor)
                  else
                    Rails.logger.debug { "######## for_investor has entity: :investor" }
                    joins(:access_rights).joins(entity: :investors)
                  end
                elsif method_defined?(:investor)
                  Rails.logger.debug { "######## for_investor has :investor" }
                  joins(:investor, parent_class_type.name.underscore => :access_rights)
                else
                  Rails.logger.debug { "######## for_investor has parent_class_type #{parent_class_type}" }
                  joins(parent_class_type.name.underscore => :access_rights).joins(entity: :investors)
                end
```

**Four-way branch, same shape as `for_rm`:**

| Model has... | Join shape | Example models |
|---|---|---|
| access_rights + investor | `joins(:access_rights).joins(:investor)` | (rare) |
| access_rights only | `joins(:access_rights).joins(entity: :investors)` | **Fund**, SecondarySale, Approval |
| investor only | `joins(:investor, parent => :access_rights)` | CapitalCommitment (investor direct; access_rights on Fund) |
| neither | `joins(parent => :access_rights).joins(entity: :investors)` | FundRatio, PortfolioInvestment |

**For `Fund.for_investor(user)` the branch hits "access_rights only":**

```sql
FROM funds
INNER JOIN access_rights
  ON access_rights.owner_type='Fund'
 AND access_rights.owner_id=funds.id
INNER JOIN entities ON entities.id = funds.entity_id
INNER JOIN investors ON investors.entity_id = entities.id
```

Each fund is paired with its access_rights AND every investor registered in that entity. The filter/merge narrows this down next.

---

```ruby
  Rails.logger.debug join_clause.to_sql
  join_clause = join_clause.merge(filter)
```

Logs the partial SQL (the `####### for_investor has ...` debug messages you saw), then merges in the access-rights filter, which appends:

```sql
AND (investors.category = access_rights.access_to_category
  OR access_rights.access_to_investor_id = investors.id
  OR access_rights.user_id = <user.id>)
```

Keep the row if the access_right was granted to the investor's category, OR the specific investor, OR directly to the user.

---

```ruby
  join_clause = join_clause.where("investors.investor_entity_id=?", user.entity_id) unless across_all_entities
```

Restrict to the investor's **own** entity. A user is registered under one investor entity at a time (`user.entity_id`), so we only keep rows where the joined investor's `investor_entity_id` matches. This is what anchors the query to "funds visible *to this LP*."

The `unless across_all_entities` lets investor advisors skip this restriction and see across all the entities they advise.

---

```ruby
  join_clause = join_clause.joins(entity: :investor_accesses).merge(InvestorAccess.approved_for_user(user, across_all_entities:))
  join_clause
end
```

Final gate — the LP's `InvestorAccess` row must be approved:

```sql
INNER JOIN investor_accesses
  ON investor_accesses.entity_id = entities.id
WHERE investor_accesses.investor_entity_id = <user.entity_id>
  AND investor_accesses.user_id          = <user.id>
  AND investor_accesses.approved         = 1
```

End of lambda — the relation returns, chainable like any other scope: `Fund.for_investor(user).where(entity_id: 157).pluck(:id)`.

---

### Instance method: `model_with_access_rights`

```ruby
def model_with_access_rights
  if %w[CapitalCommitment ...].include?(self.class.name)
    fund
  elsif %w[ExpressionOfInterest].include?(self.class.name)
    investment_opportunity
  elsif %w[Offer Interest Allocation].include?(self.class.name)
    secondary_sale
  elsif %w[ApprovalResponse].include?(self.class.name)
    approval
  elsif %w[Kpi].include?(self.class.name)
    kpi_report
  elsif %w[DealInvestor].include?(self.class.name)
    deal
  else
    self
  end
end
```

**Technical:** mirror of `parent_class_type` at the *instance* level. Returns the parent **record** (not class) — so `commitment.model_with_access_rights` returns the Fund record, `fund.model_with_access_rights` returns `self`.

**Functional:** used by UI ("share this with") and policies ("is this user allowed to see this commitment?") — callers call this to get the record whose `access_rights` they should inspect.

---

## Part 3 — How This Plays at LP Login

### The chain for `Fund.for_investor(lp_user)`

1. LP logs in via Devise — `current_user` is set.
2. Controller/view calls `Fund.for_investor(current_user)`.
3. Lambda runs with `user = lp_user`.
4. Regular LP path → `filter = AccessRight.access_filter(user)`.
5. Branch decides "Fund has access_rights" → shape #2: `joins(:access_rights).joins(entity: :investors)`.
6. Merge in filter → access_to_category / access_to_investor_id / user_id match.
7. Add `investors.investor_entity_id = user.entity_id`.
8. Add `joins(entity: :investor_accesses).merge(approved_for_user)`.
9. MySQL runs one query; returns the funds the LP may see.

### Why you got zero funds for entity 157 earlier

The core join is `INNER JOIN access_rights ON ... AND access_rights.owner_id=funds.id`. If **zero** access_rights rows exist for any fund in entity 157, the INNER JOIN annihilates every row. Creating one `AccessRight.create!(owner_type: 'Fund', owner_id: fund.id, user_id: lp.id, entity_id: 157)` added a matching row, and the LP immediately saw that fund.

### Why it matters for LP Assistant

`LpChatProvider#accessible_funds` calls `Fund.for_investor(analyst).where(entity_id: support_agent.entity_id)`. The resulting fund ids become the trusted `accessible_fund_ids` passed into `RunQueryTool`. Every SQL query the LLM writes gets scoped at runtime by `{FUND_IDS}` substitution. If `for_investor` returns `[1]`, the LLM's effective read window is `WHERE fund_id IN (1)` — no matter what query it writes.

The LLM never touches `access_rights` or `investor_accesses`. Its entire visibility is clamped by this one scope at the provider layer.

---

## Part 4 — Cheat Sheet

| Concept | Syntax | When |
|---|---|---|
| Include a concern | `include ForInvestor` | Inside a model |
| Start a concern | `extend ActiveSupport::Concern` | Top of the module |
| Run at include-time | `included do ... end` | Scopes, callbacks, associations |
| Define class methods | `class_methods do ... end` or `def self.foo` inside `included do` | Called on the class |
| Define instance methods | Plain `def foo` at module top level | Called on an instance |
| Define a scope | `scope :name, ->(args) { where(...) }` | Chainable class method returning a Relation |
| Lambda | `->(x) { ... }` or `lambda { |x| ... }` | Proc with strict arity |
| Runtime reflection | `method_defined?(:assoc)` | Check if an association exists at runtime |
| Four-way branch | `if method_defined? / elsif / elsif / else` | One concern serves many schemas |
| Compose scopes | `.merge(OtherModel.scope)` | Combine WHERE clauses from another Relation |

---

## Part 5 — Related Files

- [app/packs/core/investors/models/concerns/for_investor.rb](../../app/packs/core/investors/models/concerns/for_investor.rb) — this file
- [app/packs/core/access_rights/models/access_right.rb](../../app/packs/core/access_rights/models/access_right.rb) — `access_filter`, `access_filter_for_rm`, `investor_granted_access_filter`
- [app/packs/core/investor_accesses/models/investor_access.rb](../../app/packs/core/investor_accesses/models/investor_access.rb) — `approved_for_user` scope
- [docs/investor_access_and_access_rights/tutorial.md](./tutorial.md) — the business tutorial on how access is granted
- [app/packs/ai/lp_assistant/services/lp_chat_provider.rb](../../app/packs/ai/lp_assistant/services/lp_chat_provider.rb) — LP Assistant caller of `Fund.for_investor`
