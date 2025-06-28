# Database Backup and Restore Process Overview

This document outlines the database backup and restore strategy, which utilizes Percona XtraBackup to create consistent, non-blocking backups of our MySQL database. Backups are stored securely in an AWS S3 bucket.

The strategy is built around two types of backups: **full** and **incremental**. This combination provides a robust and efficient point-in-time recovery solution.

## Backup Process

Our backup process is managed by the `db_backup_xtra.sh` script, which automates the creation of full and incremental backups.

### Full Backups

A full backup is a complete copy of the entire database at a specific moment.

-   **Process**: The script initiates a full backup, compresses the data, and streams it directly to the designated S3 bucket.
-   **Usage**: Full backups serve as the primary baseline for any restore operation. They are typically scheduled to run periodically (e.g., daily).

### Incremental Backups

An incremental backup captures only the data that has changed since a previous backup (either a full or another incremental).

-   **Process**: The script identifies the starting point for the backup using a **Log Sequence Number (LSN)** from the last backup. It then copies only the modified data pages, compresses them, and uploads the resulting small file to S3.
-   **Usage**: Incremental backups are lightweight and fast, making them ideal for frequent execution (e.g., hourly). They allow for fine-grained, point-in-time recovery with minimal storage overhead.

## The Critical Role of the Log Sequence Number (LSN)

The **Log Sequence Number (LSN)** is the cornerstone of our incremental backup strategy. It is a unique, ever-increasing number that MySQL assigns to every record in its transaction log.

-   **How it Works**: When a backup is taken, XtraBackup records the LSN at that exact moment. For the next incremental backup, XtraBackup uses the previous backup's LSN as a starting point and only copies data that has been modified since that LSN.
-   **Why it Matters**: This mechanism ensures that each incremental backup contains a precise and consistent set of changes. During a restore, these "delta" backups can be applied in sequence on top of a full backup to perfectly reconstruct the database to a specific point in time. The script is designed to track the LSN from the previous backup to ensure this chain of changes remains unbroken.

## Restore Process

The script provides a powerful and automated process for restoring the database from the backups stored in S3.

### 1. Automated Restore (`restore_latest_chain`)

This is the standard procedure for restoring a database to its most recent state.

-   **Find Backups**: The script first identifies the latest full backup in S3 and then finds all subsequent incremental backups that form a valid "restore chain".
-   **Prepare Full Backup**: It downloads and prepares the full backup. The preparation step (`--apply-log-only`) readies the backup to have the incremental changes applied.
-   **Apply Incrementals**: The last incremental backup is downloaded and applied to the full backup in the correct sequence. This process effectively "replays" the changes that occurred since the full backup was taken.
-   **Finalize**: After the last incremental backup is applied, a final preparation step is run to ensure the data is consistent and ready for use.

### 2. Restore Validation (`restore_test`)

Before performing a destructive restore on a primary database, the script can run a validation test.

-   **Process**: It performs the full restore process described above in a temporary location. It then starts a temporary, isolated MySQL server instance using the restored data.
-   **Verification**: The script runs checks against this test server (like counting table rows) to confirm the integrity and completeness of the restored data.
-   **Purpose**: This crucial step ensures that our backups are valid and restorable before impacting a live environment.

### 3. Promoting to Primary (`restore_primary`)

Once a backup is restored and validated, it can be promoted to become the live database.

-   **Process**: This is a destructive operation. The script stops the current MySQL service, replaces its data directory with the newly restored data, and restarts the service.
-   **Outcome**: The database is now running from the restored backup.