# Per-Job SQLite Models in Rails 8

## Problem Summary

We have a large MySQL database containing data for many funds. For heavy, fund-specific processing, each background job:

1. Extracts a fund-specific slice of data from MySQL
2. Loads it into a **fund-specific SQLite database file**
3. Processes that data using ActiveRecord-style models

Multiple jobs run **concurrently**, each processing a different fund, each with its **own SQLite database**.

### Key Requirement

> SQLite-backed models must point to the correct `sqlite_path` **only within the current job and its threads**, without affecting other jobs or the rest of the Rails app.

---

## Core Constraint in Rails / ActiveRecord

ActiveRecord connections are **bound at the class level**.

This means:

* Calling `establish_connection` on a shared model class (e.g. `FundSqlite`) is **not safe** under concurrency
* Two jobs doing this will race and silently read/write the wrong SQLite database

Therefore:

> **Shared model classes cannot dynamically switch SQLite databases safely.**

---

## Solution Overview (Simplest Safe Approach)

**Use per-job subclasses of SQLite template models.**

* Keep your existing `*Sqlite` models as **templates** (no connection bound)
* Inside each job, create **job-scoped subclasses** that:

  * Inherit schema, validations, and logic from the templates
  * Are bound to that job’s SQLite database
* Each job gets its own Ruby classes → no cross-job interference

This is:

* Concurrency-safe
* Thread-safe *within the job*
* Simple to reason about
* Fully compatible with Rails 8

---

## Step-by-Step Implementation

### 1. Define a common SQLite abstract base

```ruby
# app/models/sqlite_record.rb
class SqliteRecord < ActiveRecord::Base
  self.abstract_class = true
end
```

---

### 2. Define SQLite template models (NO connection here)

These define table names, validations, and shared logic only.

```ruby
class FundSqlite < SqliteRecord
  self.table_name = "funds"
end

class CapitalCommitmentSqlite < SqliteRecord
  self.table_name = "capital_commitments"
end
```

⚠️ Avoid hard-coded `class_name:` references in associations if possible.

---

### 3. Create a job-scoped SQLite context

This object owns:

* A job-specific SQLite connection
* Job-specific subclasses of your template models

```ruby
# app/services/sqlite_context.rb
class SqliteContext
  def initialize(sqlite_path, pool_size: 5)
    @sqlite_path = sqlite_path
    @klass_map = {}

    @base = Class.new(SqliteRecord) do
      self.abstract_class = true
    end

    @base.establish_connection(
      adapter:  "sqlite3",
      database: @sqlite_path,
      pool:     pool_size
    )
  end

  # Returns a job-scoped subclass of the template model
  def model(template_klass)
    @klass_map[template_klass] ||= Class.new(template_klass) do
      def self.connection
        @__sqlite_ctx_base.connection
      end
    end.tap do |klass|
      klass.instance_variable_set(:@__sqlite_ctx_base, @base)
    end
  end

  def disconnect!
    @base.connection_pool.disconnect!
  end
end
```

---

### 4. Use the context inside a background job

```ruby
class ProcessFundJob < ApplicationJob
  def perform(fund_id)
    sqlite_path = FundSqliteBuilder.build!(fund_id)

    ctx = SqliteContext.new(sqlite_path, pool_size: 10)

    FundS = ctx.model(FundSqlite)
    CCs   = ctx.model(CapitalCommitmentSqlite)

    fund = FundS.find(fund_id)
    total_commitments = CCs.where(fund_id: fund.id).sum(:amount)

    # Thread-safe inside the job (uses the same connection pool)
    # Thread.new { CCs.count }.join

  ensure
    ctx&.disconnect! rescue nil
    File.delete(sqlite_path) if sqlite_path && File.exist?(sqlite_path)
  end
end
```

---

## Handling Associations (Important)

Template associations like this are dangerous:

```ruby
belongs_to :fund, class_name: "FundSqlite"
```

They point to the **template class**, not the job-specific subclass.

### Recommended approach

Wire associations **inside the job** using the job-scoped classes:

```ruby
FundS = ctx.model(FundSqlite)
CCs   = ctx.model(CapitalCommitmentSqlite)

CCs.belongs_to :fund, class_name: FundS.name, foreign_key: :fund_id
```

This keeps all queries inside the correct SQLite database.

---

## Threading and Pool Size

* Threads inside a job are supported
* Set SQLite `pool_size >= number of threads`
* SQLite performs best with low write contention

Recommended:

* Single-threaded jobs where possible
* Small pools (5–10 max)

---

## Cleanup Requirements (Do Not Skip)

Always:

1. Disconnect the SQLite connection pool
2. Delete the SQLite file

Otherwise you will hit:

* File locks
* Leaked connections
* Disk bloat

---

## Why This Is the Simplest Correct Solution

* No global state mutation
* No thread-local hacks
* No dynamic `database.yml`
* No connection races
* Explicit lifecycle

**Mental model:**

> *Each job gets its own miniature ActiveRecord universe.*

---

## When This Pattern Breaks Down

This approach is not ideal if:

* You need cross-job shared writes
* You want long-lived SQLite databases
* You need polymorphic associations across DBs

For fund-scoped batch processing, however, this is the cleanest solution.

---

## Summary

* ✔ Rails 8 compatible
* ✔ Concurrency-safe
* ✔ Thread-safe per job
* ✔ Minimal complexity

Use template `*Sqlite` models + job-scoped subclasses bound to a job-owned SQLite connection.

---

## Contrast with Current Implementation (Thread-Local Connection Injection)

The implementation currently deployed in the project differs from the "Per-Job Subclasses" approach described above. Instead of generating new model classes for every job, it uses a **Thread-Local Connection Injection** pattern.

### Key Differences

| Feature | Per-Job Subclasses (Doc Strategy) | Thread-Local Injection (Current Impl) |
| :--- | :--- | :--- |
| **Model Classes** | Creates dynamic anonymous subclasses for each job (`ctx.model(Fund)`). | Uses global shared constants (`FundSqlite`). |
| **Connection** | Each subclass is bound to a specific job's connection pool. | Connection is dynamically routed per-thread via `Thread.current`. |
| **Associations** | Must be manually rewired at runtime (e.g., `belongs_to`) to point to dynamic subclasses. | Work out-of-the-box because class names (`FundSqlite`) are static and shared. |
| **Isolation** | Isolation via separate Ruby classes. | Isolation via thread-local state and connection pool patching. |
| **Safety Net** | Templates have no connection; safer against accidental writes. | Base class connects to a dummy `:memory:` DB to prevent accidental MySQL writes. |

### Why the Current Implementation Was Chosen

1.  **Association Complexity**: The "Per-Job Subclasses" approach requires complex runtime metaprogramming to rewrite `has_many` and `belongs_to` associations for every single job, which is error-prone and difficult to maintain for a large graph of models.
2.  **Drop-In Compatibility**: The current approach allows existing code (services, formulas) to use standard `FundSqlite.where(...)` calls without needing to pass around a context object (`ctx`) or dynamic class references.
3.  **Concurrency Support**: By patching the connection pool to respect `Thread.current`, multiple threads within the same process (or even same job) can safely query different SQLite databases simultaneously, or share the same one, with zero interference.

### Implementation Details (Current)

*   `ApplicationRecordSqlite` establishes a connection to a **dummy in-memory database** (`:memory:`) at boot. This acts as a firewall, ensuring these models never connect to the primary MySQL database.
*   The connection pool for `ApplicationRecordSqlite` is patched to check `Thread.current[:sqlite_scratch_connection]` before returning a connection.
*   The `WithScratchSqlite` module manages the lifecycle of per-file connection pools and injects the active connection into the current thread.

---

## Critical Analysis & Risks (Rebuttal to Thread-Local Injection)

While Thread-Local Injection offers superior developer ergonomics and association handling, it introduces specific risks that must be actively managed. This section acknowledges the trade-offs and required guardrails.

### 1. Context Propagation Risk
**Risk:** "Thread-local means job isolation" is only true if all execution context is thread-stable. Modern Ruby applications use fibers, futures (`Concurrent::Future`), and libraries that spawn internal threads. If a child thread or fiber is spawned without manually propagating `Thread.current[:sqlite_scratch_connection]`, it will lose the connection context.
**Impact:** The code will silently fall back to the dummy `:memory:` database (empty results) or fail.
**Mitigation:**
*   Ensure all concurrency constructs (threads, futures) explicitly wrap their blocks in `with_scratch_sqlite` or copy the thread-local state.
*   The system fails closed (to safe memory DB) rather than open (to MySQL), but this can lead to confusing "missing data" bugs.

### 2. Upgrade Hazards
**Risk:** The implementation relies on patching `ActiveRecord::ConnectionAdapters::ConnectionPool`. Rails internals change between major versions. Overriding `connection` and `with_connection` on the pool instance is a form of monkey-patching that may break in Rails 8.1 or 9.
**Mitigation:** The patch surface is kept minimal (only on the specific pool instance used by `ApplicationRecordSqlite`). Regular testing against Rails upgrades is required.

### 3. Pool Lifecycle Discipline
**Risk:** Maintaining a registry of connection pools keyed by file path creates a risk of memory leaks (unbounded pool growth) or file lock contention (sqlite files not being closed).
**Mitigation:** `WithScratchSqlite` must strictly manage pool lifecycle, ensuring `disconnect!` is called when a job finishes, and paths are unique to prevent collisions.

### 4. Complexity of Multiple SQLite Universes
**Risk:** Allowing different threads in the same job to speak to different SQLite files creates "multiple universes" within a single logical unit of work. Shared caches, identity maps, or memoized relations can become dangerous if they cross these boundaries.
**Mitigation:** This feature should be treated as a "power user" capability, used only when strictly necessary (e.g., parallel processing of distinct data partitions).

### Summary Recommendation
**Thread-local routing is the best practical fit** for this domain-heavy codebase because it preserves the rich graph of ActiveRecord associations without refactoring. However, it **must be treated as a carefully engineered subsystem** with strict lifecycle management and awareness of thread boundaries, rather than a simple "set it and forget it" configuration.
