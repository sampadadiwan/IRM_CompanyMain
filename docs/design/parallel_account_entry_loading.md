# Design: Parallel Loading of Account Entries

## Overview
Currently, the `AccountEntryAllocation::RunFormulas` operation runs formulas sequentially in a single thread. Historically, a separate `load_primary_db` step was used to migrate data after all formulas finished.

This design implements a producer-consumer pattern using a background thread and a thread-safe queue to start loading account entries into the primary database as soon as each formula finishes, rather than waiting for all formulas to complete.

## Proposed Architecture

### 1. Thread-Safe Queue
A `Thread::Queue` is initialized at the start of the `run_formulas` step. This queue holds the IDs of completed formulas.

### 2. Background Loader Thread
A single background thread is spawned at the beginning of `run_formulas`. This thread:
- Monitors the queue for new formula IDs.
- When an ID is received, it performs a partial migration of account entries associated with that specific formula from SQLite to the primary DB.
- Uses its own database connection from the pool (`ActiveRecord::Base.connection_pool.with_connection`).
- Terminate once it receives a `nil` signal.

### 3. Producer (Main Thread)
The main thread executes `execute_formula` sequentially. After each formula completes, it pushes the `fund_formula.id` onto the queue.

### 4. Consolidated Loading & Step Removal
The previously separate `load_primary_db` step has been removed from the operation's workflow. The loading logic is now encapsulated within the `run_formulas` step:
- The background thread handles real-time loading.
- A final `migrate_entries_to_primary(ctx)` call is made in the `ensure` block of `run_formulas` to guarantee all entries are moved, including any that might have been missed by the thread or generated outside the main loop.

## Benefits
- **Reduced Latency**: Database insertions happen concurrently with formula execution.
- **Improved Resource Utilization**: CPU and I/O tasks are interleaved.
- **Simpler Workflow**: Removing the explicit `load_primary_db` step streamlines the operation.

## Implementation Details
- **Location**: `app/services/account_entry_allocation/run_formulas.rb`
- **Methods**: `run_formulas`, `start_background_loader`, `migrate_entries_to_primary`.
- **Concurrency Safety**: Background thread handles its own connection and rescues errors to avoid crashing the main process.
