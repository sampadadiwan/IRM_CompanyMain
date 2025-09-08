# `MultiSiteUserSyncOrchestrator`

This document provides a detailed explanation of the functionality and flow of the `MultiSiteUserSyncOrchestrator` service, located at `app/packs/core/users/services/multi_site_user_sync_orchestrator.rb`.

## Overview

The `MultiSiteUserSyncOrchestrator` is a Ruby service designed to manage the synchronization of user data across various geographical regions or "sites." Its core responsibility is to determine which regions require user data updates (UPSERT) or deactivations (DISABLE) and then initiate these actions through background jobs.

The service addresses two primary synchronization needs:
1.  **UPSERT (Update or Insert)**: This involves ensuring a user's information is current in all non-primary regions where they have access.
2.  **DISABLE**: This handles the removal of a user's access from regions where they were previously active but are no longer granted access.

It's important to note that this orchestrator focuses solely on *initiating* the sync actions. The actual "marking" of a user as synced or the handling of delivery policies (e.g., what happens after all targets succeed) is left to other parts of the system.

## Functional Flow and Triggers

The service's decision-making process for user synchronization follows a clear set of rules:

### User Synchronization Flow (`self.call` and instance `call`)

The main entry point for synchronizing a single user is the `self.call` method, which then delegates to an instance method. The flow is as follows:

1.  **Initialization**: The service first prepares user-related data, normalizing region names to ensure consistency (e.g., stripping whitespace, converting to uppercase). It identifies the user's primary region, their current active regions, and any previously known regions (if provided).

2.  **Primary Region Validation**: It immediately checks if the user has a defined primary region. If not, the synchronization process is skipped, as a primary region is essential for determining non-primary targets.

3.  **UPSERT Decision and Execution**:
    *   The service identifies all regions where the user is currently active, excluding their primary region. These are the potential "targets" for an UPSERT operation.
    *   An UPSERT is triggered under two conditions:
        *   If explicitly instructed to `force_all` (e.g., for a full re-sync).
        *   If the user object indicates that it `needs_sync?` (e.g., a change in user data has occurred).
    *   If either of these conditions is met, for each identified target region, a `MultiSiteUserSyncJob` is enqueued. This job will handle the actual update or insertion of the user's data in that specific region. The job can be executed immediately or scheduled for later, depending on the `perform_now` flag.
    *   If no UPSERT is triggered (neither `force_all` nor `user.needs_sync?` is true), the UPSERT phase is skipped, indicating no changes were detected or no targets were relevant.

4.  **DISABLE Decision and Execution**:
    *   This step is executed if information about the user's `previous_regions` is available.
    *   The service compares the `previous_regions` with the `current_regions` (excluding the primary region in both cases) to identify any regions from which the user's access has been removed.
    *   For each region identified as "removed," a `MultiSiteUserSyncDisableJob` is enqueued. This job is responsible for deactivating the user's presence in that specific region. These jobs are always enqueued for later execution.

5.  **Result Reporting**: After processing both UPSERT and DISABLE decisions, the service compiles a `Result` object. This object summarizes which regions had UPSERT jobs enqueued, which had DISABLE jobs enqueued, and if the UPSERT phase was skipped, the reason for skipping. This result is then logged and returned.

### Batch Synchronization Flow (`self.sync_all`)

The `self.sync_all` method provides a way to synchronize all users marked as `syncable` in the system.

1.  **Iteration**: It retrieves a list of all users that are designated as `syncable`.
2.  **Individual Sync**: For each `syncable` user, it invokes the single-user synchronization flow (`self.call`) with `perform_now: true`. This means all sync operations for these users will attempt to execute immediately.
3.  **Error Handling**: The method includes robust error handling. If a `SyncApiClient::FatalError` occurs for any user during this batch process, the error details (user ID, email, error message) are collected.
4.  **Error Notification**: After attempting to sync all users, if any errors were collected, an email notification is sent via `EntityMailer` to report the synchronization failures.

## Data Structures

### `Result` Struct

The `Result` struct is a simple data container used to communicate the outcome of a synchronization operation. It includes:
*   `enqueued_upserts`: A list of region names where user data was updated or inserted.
*   `enqueued_disables`: A list of region names where user access was disabled.
*   `skipped_reason`: A message explaining why the UPSERT operation might have been bypassed (e.g., "no_primary_region" if the user lacks a primary region, or "no_change_or_no_targets" if no sync was needed).

## Helper Functions

The service utilizes a few private helper methods to ensure data consistency and simplify the main logic:

*   `norm(val)`: Standardizes a single region string by converting it to uppercase, removing extra spaces, and treating empty strings as `nil`.
*   `norm_list(arr)`: Processes a list of region strings, applying the `norm` function to each, removing duplicates, and sorting them for consistent comparison.
*   `non_primary(regions)`: Filters a given list of regions, returning only those that are *not* the user's primary region. This is crucial for ensuring that UPSERT and DISABLE operations target the correct secondary sites.

## [`CanonicalFingerprint`](app/packs/core/users/models/concerns/canonical_fingerprint.rb:36) Concern

This Ruby on Rails concern addresses the challenge of synchronizing user data across multiple regional instances of an application. The core problem is to determine when a user's "canonical" state has genuinely changed, warranting a sync to non-primary regions, as opposed to minor, non-critical updates.

**Key Functionality:**

*   **Canonical Change Fingerprint (CCF):** It computes a deterministic SHA-256 hexadecimal fingerprint (`ccf_hex`) based on a user's key profile fields (e.g., email, primary region), normalized role assignments, and a stable entity pointer. This ensures that only significant, predefined changes trigger a sync.
*   **`needs_sync?`:** This method determines if a user's canonical state has changed and requires synchronization. It returns `true` if there are non-primary regions to sync to and the current CCF differs from the `last_synced_ccf_hex` (or if no prior sync has occurred).
*   **`mark_synced_now!`:** After a successful synchronization, this method updates the `last_synced_ccf_hex` and `last_synced_at` fields, effectively marking the current state as synchronized.
*   **Normalization:** The concern includes various normalization helpers (e.g., `normalize_field`, `normalize_regions_array`) to ensure consistency in data representation before fingerprint generation, making the CCF idempotent and deterministic.
*   **Deterministic JSON:** It uses a `stable_json` method to generate JSON with sorted keys, guaranteeing that the JSON representation of the user and role blocks is consistent across different runs, which is crucial for deterministic fingerprinting.

In essence, [`CanonicalFingerprint`](app/packs/core/users/models/concerns/canonical_fingerprint.rb:36) provides a robust mechanism to track and trigger user data synchronization based on meaningful changes, avoiding unnecessary updates and ensuring data consistency across distributed application instances.