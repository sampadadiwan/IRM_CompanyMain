module AccountEntryAllocation
  ############################################################
  # 1. RunFormulas Operation
  ############################################################
  class RunFormulas < AllocationBaseOperation
    include Rails.application.routes.url_helpers
    include ApplicationHelper
    include WithScratchSqlite

    step :setup_start_time
    step :delete_existing_entries
    step :load_sqlite_db
    step :get_commitments
    step :run_formulas
    step :generate_fund_ratios
    step :generate_soa
    step :cleanup_sqlite
    left :cleanup_sqlite, id: :ensure_cleanup_sqlite
    step :display_generated_links

    def setup_start_time(ctx, **)
      # This is the very first step - record the start time
      ctx[:run_start_time] = Time.zone.now
      true
    end

    def load_sqlite_db(ctx, fund:, **)
      # We need to load the SQLite DB only if we are running allocations
      return true unless ctx[:run_allocations]

      notify("Loading data for fund #{fund.name}. Could take a few minutes...", :info, ctx[:user_id])

      entity_id = fund.entity_id
      fund_id = fund.id
      master_fund_id = fund.master_fund_id
      fund_ids = [fund_id, master_fund_id].compact.uniq

      script_path = Rails.root.join("script/load_sqlite3_from_mysql.sh")

      # Define unique temporary paths for this entity to allow concurrent runs
      ctx[:sqlite_path] = "/tmp/irm_data_#{fund_ids.join('_')}.sqlite3"
      ctx[:tsv_path] = "/tmp/irm_data_#{fund_ids.join('_')}.tsv"

      # Extract the primary database configuration dynamically from ActiveRecord.
      # This ensures we use the correct credentials even in test/staging environments.
      db_config = ActiveRecord::Base.connection_db_config.configuration_hash
      adapter = db_config[:adapter].to_s

      # Prepare the environment variables required by the bash script
      env = {
        "FUND_IDS" => fund_ids.join(","),
        "ADAPTER" => adapter,
        "MYSQL_HOST" => db_config[:host].to_s,
        "MYSQL_PORT" => db_config[:port].to_s,
        "MYSQL_USER" => db_config[:username].to_s,
        "MYSQL_PASS" => db_config[:password].to_s,
        "MYSQL_DB" => db_config[:database].to_s
      }

      # If the primary DB is SQLite (e.g. in development/test), tell the script
      # exactly where the source database file is located.
      env["SOURCE_SQLITE_DB"] = Rails.root.join(db_config[:database]).to_s if adapter == "sqlite3"

      # Execute the external migration script and wait for it to finish.
      # The script handles the heavy lifting of bulk exporting/importing via TSV.
      if Rails.env.development? && File.exist?(ctx[:sqlite_path])
        Rails.logger.debug { "Skipping SQLite DB load in development as file already exists at #{ctx[:sqlite_path]}" }
        success = true
      else
        success = system(env, "bash #{script_path}")
      end

      if success
        Rails.logger.debug { "Successfully loaded isolated SQLite DB for Entity ID: #{entity_id}" }
        with_scratch_sqlite(ctx[:sqlite_path]) do
          AccountEntrySqlite.where(allocation_run_id: ctx[:allocation_run_id]).delete_all
          count = AccountEntrySqlite.where(fund_id: fund.id).count
          Rails.logger.debug { "Loaded #{count} account_entries for fund #{fund.name} into isolated SQLite DB" }
        end
        notify("Loaded DB with account_entries for fund #{fund.name}", :info, ctx[:user_id])
        true
      else
        error_msg = "Failed to load isolated SQLite DB for Entity ID: #{entity_id}"
        notify(error_msg, :info, ctx[:user_id])
        Rails.logger.error error_msg
        ctx[:error] = error_msg
        false
      end
    end

    def cleanup_sqlite(ctx, **)
      # Clean up the temporary isolated files from /tmp to keep the system lean
      sqlite_path = ctx[:sqlite_path]
      tsv_path = ctx[:tsv_path]

      # First, disconnect the pool to close all file handles
      AccountEntryAllocation::WithScratchSqlite.disconnect_pool(sqlite_path) if sqlite_path

      [sqlite_path, tsv_path].compact.each do |path|
        if File.exist?(path)
          Rails.logger.debug { "Cleaning up isolated temporary file: #{path}" }
          File.delete(path) unless Rails.env.development?
        end

        # Also cleanup WAL files if they exist
        wal_path = "#{path}-wal"
        shm_path = "#{path}-shm"
        [wal_path, shm_path].each do |extra_path|
          File.delete(extra_path) if File.exist?(extra_path) && !Rails.env.development?
        end
      end

      true
    end

    # Now we have all commitments loaded into the SQLite DB, so load it from there
    def get_commitments(ctx, fund:, end_date:, sample:, **)
      # We need to load the commitments only if we are running allocations
      return true unless ctx[:run_allocations]

      # Load commitments once for all formulas
      with_scratch_sqlite(ctx[:sqlite_path]) do
        commitments = if fund.custom_fields[:sample_commitment_ids_for_allocation].present?
                        CapitalCommitmentSqlite.where(fund_id: fund.id, id: fund.custom_fields[:sample_commitment_ids_for_allocation].split(",").map(&:strip))
                      else
                        CapitalCommitmentSqlite.where(fund_id: fund.id, commitment_date: ..end_date)
                      end
        # commitments = commitments.includes(:entity, :fund, :investor_kyc)
        commitments = commitments.limit(3) if sample
        ctx[:commitments] = commitments.to_a # Load into memory since we'll be closing the connection
      end
      true
    end

    def run_formulas(ctx, **)
      return true unless ctx[:run_allocations]

      fund = ctx[:fund]
      ctx[:start_date]
      ctx[:end_date]

      # Used to update the created account_entries. See CreateAccountEntry
      ctx[:form_type_id] = fund.entity.form_types.where(name: "AccountEntry").last
      ctx[:bulk_insert_records] = []

      formulas = get_formulas(ctx)

      # Ensure that the portfolio_investments are up to date before running formulas. As this may compute the expenses for the portfolio investments
      fund.resave_portfolio_investments

      ctx[:formula_count] = formulas.count

      # Mutex to ensure only one thread migrates from SQLite to Primary at a time
      ctx[:migration_mutex] = Thread::Mutex.new

      queue = Thread::Queue.new
      loader_thread = start_background_loader(ctx, queue)
      # Pass the queue to the main thread context, this is so heavy allocations can push to it
      # without having to pass it around everywhere.
      ctx[:queue] = queue

      with_scratch_sqlite(ctx[:sqlite_path]) do
        formulas.each_with_index do |fund_formula, index|
          execute_formula(ctx, fund_formula, index)
          Rails.logger.info { "Completed formula #{index + 1} of #{formulas.count}. Pushing to loader queue #{fund_formula.id}." }
          # Push the completed formula ID to the queue for parallel loading
          queue << fund_formula.id
        end
      ensure
        # Signal the loader thread to finish and wait for it
        queue << nil
        loader_thread&.join

        # Mark all as migrated to avoid double processing in final catch-all
        # migrate_entries_to_primary(ctx) will now only pick up leftovers
        migrate_entries_to_primary(ctx, final_check: true)

        # Update status only in the final run (when final_check is true)
        ctx[:allocation_run]&.update_column(:status, "Success")

      end

      true
    end

    def delete_existing_entries(ctx, **)
      # We need to delete the existing entries only if we are running allocations
      return true unless ctx[:run_allocations]

      # In this step, we only soft-delete from the primary DB.
      # This ensures the migration script (load_sqlite3_from_mysql.sh) sees them as deleted
      # but the physical rows still exist with the correct number of columns during the export.
      delete_existing_primary_entries(ctx)
      true
    end

    def display_generated_links(ctx, fund:, start_date:, end_date:, user_id:, **)
      # We need to display the generated links only if we are running allocations
      return true unless ctx[:run_allocations]

      run_start_time = ctx[:run_start_time]
      time_taken = (Time.zone.now - run_start_time).to_i

      msg = "Done running #{ctx[:formula_count]} formulas for #{start_date} - #{end_date} in #{time_taken} seconds"

      entry_types = [
        ['', 'View Account Entries'],
        ['Expense', 'View Expenses'],
        ['Portfolio Allocation', 'View Portfolio Allocation']
      ]

      links_html = entry_types.map do |entry_type, label|
        query_params = ransack_query_params_multiple([
                                                       ['allocation_run_id', :eq, ctx[:allocation_run_id]],
                                                       ["reporting_date", :eq, I18n.l(end_date, format: :default)],
                                                       [:entry_type, :eq, entry_type]
                                                     ])
        ActionController::Base.helpers.link_to(label, account_entries_path(fund_id: fund.id, filter: true, q: query_params), class: 'mb-1 badge  bg-primary-subtle text-primary', target: '_blank', rel: 'noopener')
      end.join

      notify("#{msg}<br>#{links_html}", :success, user_id)
    end

    # rubocop:disable Lint/RescueException
    def generate_fund_ratios(ctx, fund:, start_date:, end_date:, user_id:, **)
      if ctx[:fund_ratios]
        begin
          FundRatiosJob.perform_now(fund.id, nil, end_date, user_id, true, return_cash_flows: ctx[:return_cash_flows])
          msg = "Done generating fund ratios for #{start_date} - #{end_date}"
          Rails.logger.debug msg
          notify(msg, :success, user_id)
          true
        rescue Exception => e
          Rails.logger.error e.backtrace
          msg = "Error generating fund ratios for #{start_date} - #{end_date}: #{e.message}"
          Rails.logger.error msg
          notify(msg, :danger, user_id)
          false
        end
      else
        Rails.logger.debug "Skipping fund ratios generation"
        true
      end
    end
    # rubocop:enable Lint/RescueException

    # rubocop:disable Lint/RescueException
    def generate_soa(ctx, fund:, start_date:, end_date:, user_id:, template_id:, **)
      if ctx[:generate_soa]
        begin
          CapitalCommitmentSoaJob.perform_later(fund.id, nil, start_date.to_s, end_date.to_s, user_id, template_id:)
          msg = "Done generating Investor Statement for #{start_date} - #{end_date}"
          Rails.logger.debug msg
          notify(msg, :success, user_id)
          true
        rescue Exception => e
          Rails.logger.error e.backtrace
          msg = "Error generating Investor Statement for #{start_date} - #{end_date}: #{e.message}"
          Rails.logger.error msg
          notify(msg, :danger, user_id)
          false
        end
      else
        Rails.logger.debug "Skipping Investor Statement generation"
        true
      end
    end
    # rubocop:enable Lint/RescueException

    private

    def start_background_loader(ctx, queue)
      Thread.new do
        Rails.logger.debug "Starting background loader thread for Account Entries"
        # We must wrap the whole thread loop in with_scratch_sqlite if we need to access scratch DB
        # But migrate_entries_to_primary already does it.
        # The issue is that migrate_entries_to_primary is called INSIDE the loop.
        # Let's ensure ActiveRecord is ready.
        ActiveRecord::Base.connection_pool.with_connection do
          loop do
            fund_formula_id = queue.pop
            Rails.logger.debug { "Loader thread picked up fund_formula_id: #{fund_formula_id.inspect}" }
            break if fund_formula_id.nil?

            # We must wrap this in with_scratch_sqlite inside the thread
            # because the main thread's with_scratch_sqlite connections are thread-local
            migrate_entries_to_primary(ctx, fund_formula_id: fund_formula_id)
          rescue StandardError => e
            Rails.logger.error "Error in background loader thread: #{e.message}"
            Rails.logger.error e.backtrace.join("\n")
            # We don't raise here to keep the thread alive for other formulas,
            # but the final load call in run_formulas will catch missing entries.
          end
        end
      end
    end

    # rubocop:disable Metrics/BlockLength, Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
    def migrate_entries_to_primary(ctx, fund_formula_id: nil, final_check: false)
      sqlite_path = ctx[:sqlite_path]
      return false unless sqlite_path && File.exist?(sqlite_path)

      # Use the mutex from context to ensure only one thread performs migration at a time.
      # This prevents race conditions where two threads might read the same 'unmigrated' rows
      # before either has marked them as migrated.
      ctx[:migration_mutex].synchronize do
        # Ensure we have a connection to the scratch DB
        # If fund_formula_id is nil, this is called from main thread ensure block
        # which might be outside its own with_scratch_sqlite block
        with_scratch_sqlite(sqlite_path) do
          query = AccountEntrySqlite.generated.where(fund_id: ctx[:fund].id, allocation_run_id: ctx[:allocation_run_id])
          query = query.where(fund_formula_id: fund_formula_id) if fund_formula_id

          # Only pick up rows that haven't been marked as migrated yet
          query = query.where(migrated: false)

          total_count = query.count
          return true if total_count.zero?

          label = if fund_formula_id
                    "Formula #{fund_formula_id}"
                  else
                    (final_check ? "Final Catch-all" : "All Remaining")
                  end
          Rails.logger.debug { "##### Migrating #{total_count} entries for #{label} from SQLite to primary DB ######" }

          batch_size = 5000
          now = Time.zone.now

          # We process in batches to avoid huge memory usage
          # NOTE: query.find_in_batches with explicit primary key ordering is safer for SQLite
          # Using a simple LIMIT/OFFSET loop here to be explicit and avoid any potential find_in_batches issues with the custom SQLite setup
          processed = 0
          loop do
            batch = query.limit(batch_size).to_a
            break if batch.empty?

            insert_data = batch.map do |sqlite_entry|
              attrs = sqlite_entry.attributes.except("id", "created_at", "updated_at", "deleted_at", "generated_deleted", "migrated")
              # Sometimes the parent_type may have the Sqlite namespace, remove it, as we want to pull this data back to the primary DB
              attrs["parent_type"] = attrs["parent_type"].gsub("Sqlite", "") if attrs["parent_type"].present?
              attrs.merge("created_at" => now, "updated_at" => now)
              if attrs["json_fields"].is_a?(String)
                begin
                  attrs["json_fields"] = JSON.parse(attrs["json_fields"])
                rescue JSON::ParserError
                  attrs["json_fields"] = {}
                end
              end
              attrs["json_fields"] ||= {}
              attrs["json_fields"]["sqlite_id"] = sqlite_entry.id.to_s
              attrs
            end

            if insert_data.any?
              # Use a transaction for each batch to ensure consistency while minimizing lock duration
              AccountEntry.transaction do
                AccountEntry.insert_all(insert_data)
              end

              # Mark these as migrated in the SQLite DB to prevent double migration
              batch_ids = batch.map(&:id)
              update_count = AccountEntrySqlite.where(id: batch_ids).update_all(migrated: true)
              Rails.logger.info { "##### SQLITE UPDATE: Marked #{update_count} records as migrated for #{label} #####" }
            else
              Rails.logger.debug { "##### NO DATA: No entries to migrate in this batch for #{label} #####" }
            end

            processed += batch.size

            processed_count = [processed, total_count].min
            notify("Migrating #{processed_count} of #{total_count} entries for #{label} to primary DB", :info, ctx[:user_id]) if final_check
          end
        end
      end

      # Update parent_id for AccountEntry parents to their new primary IDs in MySQL
      relink_account_entry_parents(ctx) if final_check

      true
    end
    # rubocop:enable Metrics/BlockLength, Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity

    def relink_account_entry_parents(ctx)
      allocation_run_id = ctx[:allocation_run_id]
      return unless allocation_run_id

      msg = "Relinking AccountEntry parent relationships for allocation run #{allocation_run_id}"
      Rails.logger.debug { msg }
      notify(msg, :info, ctx[:user_id])

      # We use a direct SQL update to relink parents.
      # This joins the table on itself, matching the child's old parent_id (SQLite)
      # with the parent's stored sqlite_id in the json_fields.
      # JSON_EXTRACT(json_fields, '$.sqlite_id') is used to retrieve the SQLite ID in MySQL.
      # We cast it to UNSIGNED to ensure proper comparison with parent_id.
      sql = <<-SQL.squish
        UPDATE account_entries AS child
        INNER JOIN account_entries AS parent ON
          child.parent_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(parent.json_fields, '$.sqlite_id')) AS UNSIGNED)
          AND parent.allocation_run_id = child.allocation_run_id
          AND parent.entry_type = 'AccountEntry'
        SET child.parent_id = parent.id
        WHERE child.allocation_run_id = ?
          AND child.parent_type = 'AccountEntry'
          AND child.parent_id IS NOT NULL
      SQL

      AccountEntry.connection.execute(AccountEntry.sanitize_sql_for_assignment([sql, allocation_run_id]))
    end

    def get_formulas(ctx)
      fund     = ctx[:fund]
      rule_for = ctx[:rule_for]
      tag_list = ctx[:tag_list]

      formulas = FundFormula.enabled.where(fund_id: fund.id).order(sequence: :asc).includes(:fund, :entity)
      formulas = formulas.where(rule_for: rule_for) if rule_for.present?
      formulas = formulas.with_tags(tag_list.split(",")) if tag_list.present?
      formulas
    end

    def delete_existing_primary_entries(ctx)
      fund       = ctx[:fund]
      start_date = ctx[:start_date]
      end_date   = ctx[:end_date]
      user_id    = ctx[:user_id]
      formulas   = get_formulas(ctx)

      formula_ids = formulas.pluck(:id)

      # We chunk formula_ids to avoid potential issues with very large IN clauses
      # and to keep the deletion scope manageable.
      formula_ids.each_slice(100) do |chunked_ids|
        # Delete existing fund account entries for the formulas from primary DB
        # NOTE: We use .delete_all to perform a hard delete in batches to avoid locking the table.
        # This is the very first step of the run.
        primary_account_entries = AccountEntry.where(fund_id: fund.id, reporting_date: start_date..end_date)
        primary_account_entries = primary_account_entries.where(fund_formula_id: chunked_ids).where(deleted_at: nil)

        batch_size = 5_000
        idx = 1
        loop do
          msg = "Cleaning up primary account entries for #{fund.name} in the run period: #{start_date} - #{end_date}, formula chunk batch #{idx}"
          Rails.logger.debug { msg }
          notify(msg, :info, user_id)

          deleted = primary_account_entries.limit(batch_size).delete_all
          break if deleted < batch_size

          sleep(0.1) # Small pause to reduce contention
          idx += 1
        end
      end
    end

    def execute_formula(ctx, fund_formula, index)
      ctx[:formula_index] = index
      start_time = Time.zone.now

      # Call sub-operation to run the formula
      # We re-use the same ctx for sub-ops, but add the current fund_formula:
      sub_ctx = ctx.merge(fund_formula: fund_formula)

      result = AccountEntryAllocation::RunFormula.call(sub_ctx)
      raise result[:error] if result.failure? && result[:error].present?

      # Update execution_time
      fund_formula.update_column(:execution_time, ((Time.zone.now - start_time) * 1000).to_i)

      # Provide notification
      notify("Completed #{index + 1} of #{ctx[:formula_count]}: #{fund_formula.name}", :success, ctx[:user_id])
    rescue StandardError => e
      error_message = "Error in Formula #{fund_formula.sequence}: #{fund_formula.name} : #{e.message}"
      notify(error_message, :danger, ctx[:user_id])
      Rails.logger.debug { error_message }
      ctx[:allocation_run]&.update_column(:status, error_message)
      raise e
    end
  end
end
