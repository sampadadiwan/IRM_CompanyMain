# Rebuttal: Advantages of Thread-Local Connection Injection over Per-Job Subclasses

I have reviewed the proposed "Per-Job Subclasses" approach for managing concurrent SQLite databases in Rails 8. While I agree with the core constraint—that shared model classes cannot safely switch connections globally—I believe the implemented **Thread-Local Connection Injection** strategy offers significant practical advantages for our specific codebase, while maintaining the same safety guarantees.

## 1. Safety and Isolation (Parity Achieved)

The primary motivation for Per-Job Subclasses is preventing race conditions where one job changes the connection for another. The current implementation achieves this identical isolation through a different mechanism:

*   **Thread-Local Routing**: Instead of changing the class-level connection, we patch the connection pool to check `Thread.current`. This means Job A (Thread 1) and Job B (Thread 2) effectively see different connections when querying the same `FundSqlite` class.
*   **Safety Firewall**: By establishing a connection to a dummy `:memory:` database at boot, we ensure that `FundSqlite` is physically incapable of connecting to the primary MySQL database by default. If the thread-local logic were to fail, queries would harmlessly hit an empty memory DB rather than corrupting production data.

## 2. The Association Complexity Problem

The fatal flaw in the Per-Job Subclasses approach is the handling of associations.

In the proposal:
> *Template associations like `belongs_to :fund, class_name: "FundSqlite"` are dangerous... Recommended approach: Wire associations inside the job using the job-scoped classes.*

This requires:
1.  Removing all association definitions from the template models.
2.  Manually redefining every `has_many`, `belongs_to`, and `has_one` inside `perform` for every job-scoped subclass.
3.  Maintaining this dynamic wiring logic in parallel with the schema.

For a complex domain model with deep relationship graphs (Fund -> Commitments -> Adjustments -> Investors), this creates a massive maintenance burden and introduces a high risk of "wiring bugs" where a relationship is forgotten or misconfigured in the job context.

**In the Current Implementation:**
Associations "just work." Because `FundSqlite` is a static constant, `belongs_to :fund, class_name: 'FundSqlite'` resolves correctly. The connection management layer ensures that when `capital_commitment.fund` is accessed, the query runs against the correct thread-local SQLite file.

## 3. Drop-In Compatibility

The Per-Job Subclasses approach requires refactoring all service objects and formulas to accept dynamic class references (e.g., passing `FundClass` instead of just using `FundSqlite`).

**In the Current Implementation:**
Existing services (e.g., `RunFormulas`) require zero changes. They continue to call `FundSqlite.where(...)` as normal. The infrastructure handles the routing transparently.

## 4. Concurrency within Jobs

The proposal notes:
> *Thread-safe inside the job (uses the same connection pool)*

The Current Implementation goes further: it supports **concurrent threads within the same job using DIFFERENT databases** if needed, or sharing the same one. The `WithScratchSqlite` module creates a registry of pools keyed by file path, allowing fine-grained control over which file a specific thread interacts with, simply by wrapping the code in a block.

## Summary

The "Per-Job Subclasses" pattern is theoretically pure but practically expensive due to the need for manual association rewiring and dependency injection refactoring. The "Thread-Local Connection Injection" pattern implemented provides the same isolation guarantees (verified by stress tests) with significantly lower friction and maintenance overhead.
