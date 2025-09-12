class PartitionAccountEntriesByYear < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!  # important: large table ops cannot run inside a single transaction

  BATCH_SIZE = 50_000

  def up
    say_with_time "Creating partitioned table account_entries_new" do
      execute <<~SQL

        CREATE TABLE account_entries_new (
            id BIGINT NOT NULL AUTO_INCREMENT,
            capital_commitment_id BIGINT,
            entity_id BIGINT NOT NULL,
            fund_id BIGINT NOT NULL,
            investor_id BIGINT,
            form_type_id BIGINT,
            folio_id VARCHAR(40),
            reporting_date DATE NOT NULL,
            entry_type VARCHAR(50),
            name VARCHAR(125),
            amount_cents DECIMAL(30,8) DEFAULT 0.0,
            notes TEXT,
            created_at DATETIME NOT NULL,
            updated_at DATETIME NOT NULL,
            explanation TEXT,
            cumulative BOOLEAN DEFAULT FALSE,
            period VARCHAR(25),
            parent_type VARCHAR(255),
            parent_id BIGINT,
            `generated` BOOLEAN DEFAULT FALSE,
            folio_amount_cents DECIMAL(30,8) DEFAULT 0.0,
            exchange_rate_id BIGINT,
            fund_formula_id BIGINT,
            rule_for VARCHAR(10) DEFAULT 'Accounting',
            json_fields JSON,
            import_upload_id BIGINT,
            deleted_at DATETIME,
            generated_deleted DATETIME AS (ifnull(`deleted_at`,_utf8mb4'1900-01-01 00:00:00')) VIRTUAL NOT NULL,
            tracking_amount_cents DECIMAL(20,2) DEFAULT 0.0,
            allocation_run_id BIGINT,
            parent_name VARCHAR(255),
            commitment_name VARCHAR(255),
            ref_id INT NOT NULL DEFAULT 0,

            PRIMARY KEY (id, reporting_date),

            UNIQUE KEY index_accounts_on_unique_fields (
              name, fund_id, capital_commitment_id, entry_type,
              reporting_date, cumulative, deleted_at,
              parent_type, parent_id, ref_id, amount_cents
            ),
            KEY index_account_entries_on_reporting_date (reporting_date),
            KEY index_account_entries_on_fund_id (fund_id),
            KEY index_account_entries_on_entity_id (entity_id),
            KEY index_account_entries_on_investor_id (investor_id),
            KEY index_account_entries_on_allocation_run_id (allocation_run_id),
            KEY index_account_entries_on_capital_commitment_id (capital_commitment_id),
            KEY index_account_entries_on_exchange_rate_id (exchange_rate_id),
            KEY index_account_entries_on_fund_formula_id (fund_formula_id),
            KEY index_account_entries_on_import_upload_id (import_upload_id),
            KEY index_account_entries_on_form_type_id (form_type_id)
        )
        PARTITION BY RANGE (YEAR(reporting_date)) (
            PARTITION p2023 VALUES LESS THAN (2024),
            PARTITION p2024 VALUES LESS THAN (2025),
            PARTITION p2025 VALUES LESS THAN (2026),
            PARTITION pmax  VALUES LESS THAN MAXVALUE
        );
      SQL
    end

    say_with_time "Copying data in batches of #{BATCH_SIZE}" do
      max_id = select_value("SELECT MAX(id) FROM account_entries").to_i
      start_id = 1

      while start_id <= max_id
        end_id = start_id + BATCH_SIZE - 1
        say "Copying rows #{start_id}–#{end_id}", true

        execute <<~SQL
          INSERT INTO account_entries_new (
            id, capital_commitment_id, entity_id, fund_id,
            investor_id, form_type_id, folio_id, reporting_date,
            entry_type, name, amount_cents, notes, created_at,
            updated_at, explanation, cumulative, period,
            parent_type, parent_id, `generated`, folio_amount_cents,
            exchange_rate_id, fund_formula_id, rule_for, json_fields,
            import_upload_id, deleted_at, tracking_amount_cents,
            allocation_run_id, parent_name, commitment_name, ref_id
          )
          SELECT
            id, capital_commitment_id, entity_id, fund_id,
            investor_id, form_type_id, folio_id, reporting_date,
            entry_type, name, amount_cents, notes, created_at,
            updated_at, explanation, cumulative, period,
            parent_type, parent_id, `generated`, folio_amount_cents,
            exchange_rate_id, fund_formula_id, rule_for, json_fields,
            import_upload_id, deleted_at, tracking_amount_cents,
            allocation_run_id, parent_name, commitment_name, ref_id
          FROM account_entries
          WHERE id BETWEEN #{start_id} AND #{end_id};
        SQL

        start_id = end_id + 1
      end
    end

    say_with_time "Swapping tables" do
      execute <<~SQL
        RENAME TABLE account_entries TO account_entries_old,
                     account_entries_new TO account_entries;
      SQL
    end
  end

  def down
    say_with_time "Rolling back partitioning" do
      execute <<~SQL
        RENAME TABLE account_entries TO account_entries_new,
                     account_entries_old TO account_entries;
      SQL
      execute "DROP TABLE IF EXISTS account_entries_new;"
    end
  end
end
