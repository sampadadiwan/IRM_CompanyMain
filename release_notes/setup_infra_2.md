**Overview**:
This PR introduces significant infrastructure setup and deployment enhancements, including AMI provisioning, database restore improvements, and application configuration updates.

**Motivation**:
This change was made to streamline the deployment process, improve infrastructure provisioning, enhance database management capabilities, and refine application configurations for better performance and maintainability. It addresses the need for more robust and automated environment setup.

**What Changed**:
*   **Infrastructure Provisioning (Packer AMI Templates)**:
    *   [`config/deploy/templates/packer/appserver.ami.pkr.hcl`](config/deploy/templates/packer/appserver.ami.pkr.hcl): Added comprehensive inline shell scripts for installing essential software on the application server AMI, including Zsh, RVM (with Ruby 3.4.4), Docker, MySQL client, LibreOffice, Monit, Logrotate, Nginx, pdftk, pv, unzip, imagemagick, and ffmpeg.
    *   [`config/deploy/templates/packer/db_redis_es.ami.pkr.hcl`](config/deploy/templates/packer/db_redis_es.ami.pkr.hcl): Added extensive inline shell scripts for installing MySQL 8.4.6 (Oracle/Percona) with remote access configuration, Docker with auto-start for Elasticsearch and Redis via cron, Percona XtraBackup 8.4 LTS, lz4, zstd, and AWS CLI v2. MySQL root user setup now uses `caching_sha2_password` and grants remote privileges.
    *   [`config/deploy/templates/packer/observability.ami.pkr.hcl`](config/deploy/templates/packer/observability.ami.pkr.hcl): Added Zsh installation.
*   **Deployment Configuration (Capistrano)**:
    *   [`config/deploy.rb`](config/deploy.rb):
        *   Updated Puma configuration with explicit `puma_threads` and `puma_restart_command`.
        *   Introduced `skip_notification` flag to control deployment notifications.
        *   Modified database restore Rake tasks to use `db:restore_primary_db` and `db:restore_replica_db`.
        *   Ensured `RAILS_MASTER_KEY` is written to a file on the remote server during deployment setup.
        *   Added Puma configuration file upload (`puma.rb.erb`) and socket directory creation during `IRM:setup`.
        *   Adjusted Nginx symlink target name.
    *   [`config/deploy/staging.rb`](config/deploy/staging.rb): Updated server definitions, including commented-out load balancer and primary/app/web/db roles.
    *   [`config/deploy/templates/puma.rb.erb`](config/deploy/templates/puma.rb.erb): Simplified Puma configuration, hardcoding threads and workers, and binding to a Unix socket.
    *   [`config/deploy/templates/maintenance.erb`](config/deploy/templates/maintenance.erb): Renamed file.
*   **Application Logic**:
    *   [`app/packs/core/base/models/report.rb`](app/packs/core/base/models/report.rb): Added `allow_custom_grid_columns?` to determine if a report's model supports custom grid columns based on `STANDARD_COLUMNS` constant.
    *   [`app/packs/core/base/services/db_restore_service.rb`](app/packs/core/base/services/db_restore_service.rb): Added `stop_instance_flag` to `DbRestoreService.run!` to optionally skip stopping the EC2 instance after DB restore.
    *   [`app/packs/core/base/views/reports/_card.html.erb`](app/packs/core/base/views/reports/_card.html.erb): Conditionally renders "Configure Grid" link based on `report.allow_custom_grid_columns?`.
    *   [`app/packs/core/documents/views/documents/show.html.erb`](app/packs/core/documents/views/documents/show.html.erb): Added a confirmation popup for sending documents.
    *   [`app/packs/funds/capital_commitments/services/account_entry_pivot.rb`](app/packs/funds/capital_commitments/services/account_entry_pivot.rb): Refactored `call` and `chart` methods for `AccountEntryPivot` service, improving data structuring, handling of breakdown and cumulative amounts, and enhancing comments for clarity.
*   **Credentials**:
    *   [`config/credentials/staging.yml.enc`](config/credentials/staging.yml.enc): Updated encrypted staging credentials.

**Refactoring / Behavior Changes**:
*   **Infrastructure Setup**: The AMI provisioning process is significantly enhanced, moving from simple script execution to detailed inline installations of various software, ensuring a more complete and consistent environment setup.
*   **Deployment Flow**: Capistrano deployment scripts are refined to better manage Puma, Sidekiq, and Nginx services, and to handle Rails master key distribution more robustly. The database restore process is also updated with more specific Rake tasks.
*   **Database Restore Service**: The `DbRestoreService` now offers more control by allowing the skipping of instance termination, which can be useful for debugging or specific recovery scenarios.
*   **Report Grid Configuration**: The ability to configure custom grid columns for reports is now dynamically controlled based on model definitions.
*   **Document Sending Confirmation**: A user-facing confirmation has been added before sending documents, improving user experience and preventing accidental sends.
*   **Account Entry Pivot Logic**: The `AccountEntryPivot` service has undergone a significant internal refactoring to improve its data processing and charting capabilities, especially concerning data aggregation and breakdown.

**Testing**:
*   **Automated Tests**: Existing unit and integration tests for `Report` model, `DbRestoreService`, and `AccountEntryPivot` service should be run to ensure no regressions.
*   **Manual Testing**:
    *   Verify AMI builds successfully with all specified software installed.
    *   Test deployment to staging environment, ensuring Puma, Sidekiq, and Nginx start correctly.
    *   Confirm database restore functionality, including the new `stop_instance_flag`.
    *   Verify the "Configure Grid" link appears correctly for reports with `STANDARD_COLUMNS` and is hidden otherwise.
    *   Test sending documents to confirm the new confirmation popup appears and functions as expected.
    *   Validate `AccountEntryPivot` service functionality, especially with and without breakdown/cumulative options, ensuring data accuracy in reports and charts.

**Impact**:
*   **Deployment Reliability**: Improved AMI provisioning and deployment scripts are expected to lead to more reliable and consistent environment setups.
*   **Performance**: Puma configuration changes might impact application performance; monitoring is recommended.
*   **Maintainability**: Refactored `AccountEntryPivot` service improves code clarity and maintainability.
*   **Security**: Updated MySQL root password handling and credential management contribute to better security practices.
*   **User Experience**: Document sending confirmation enhances user experience.

**Review Focus**:
*   **Packer Scripts**: Review the extensive inline shell scripts in Packer templates ([`config/deploy/templates/packer/appserver.ami.pkr.hcl`](config/deploy/templates/packer/appserver.ami.pkr.hcl), [`config/deploy/templates/packer/db_redis_es.ami.pkr.hcl`](config/deploy/templates/packer/db_redis_es.ami.pkr.hcl), [`config/deploy/templates/packer/observability.ami.pkr.hcl`](config/deploy/templates/packer/observability.ami.pkr.hcl)) for correctness, idempotency, and security best practices.
*   **Deployment Configuration**: Verify all Capistrano changes in [`config/deploy.rb`](config/deploy.rb) and [`config/deploy/staging.rb`](config/deploy/staging.rb) are correct and align with deployment strategy. Pay close attention to Puma and Nginx configurations.
*   **`DbRestoreService`**: Confirm the logic around `stop_instance_flag` is sound and does not introduce unintended side effects.
*   **`AccountEntryPivot` Refactoring**: Thoroughly review the refactored `call` and `chart` methods in [`app/packs/funds/capital_commitments/services/account_entry_pivot.rb`](app/packs/funds/capital_commitments/services/account_entry_pivot.rb) to ensure data integrity and correct aggregation/breakdown logic.
*   **Security**: Review the updated [`config/credentials/staging.yml.enc`](config/credentials/staging.yml.enc) (though encrypted, ensure the process for updating it is secure) and the MySQL password setup in Packer.