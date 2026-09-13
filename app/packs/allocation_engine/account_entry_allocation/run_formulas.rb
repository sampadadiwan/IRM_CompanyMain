# AccountEntryAllocationJob.perform_now 320, Date.parse("Thu, 01 Jan 2026"), Date.parse("Tue, 31 Mar 2026"), rule_for: "Accounting", tag_list: nil, run_allocations: true, explain: true, user_id: 24, generate_soa: false, template_id: nil, fund_ratios: false, sample: false, allocation_run_id: 1500
require 'fileutils'
require 'shellwords'

module AccountEntryAllocation
  ############################################################
  # 1. RunFormulas Operation
  ############################################################
  class RunFormulas < AllocationBaseOperation
    include Rails.application.routes.url_helpers
    include ApplicationHelper
    include WithScratchSqlite

    # Check results that make persist_check_results store them and build the report.
    FLAGGED_CHECK_RESULTS = %w[fail warn].freeze

    step :setup_start_time
    # Before anything is deleted: a failed pre-run check must leave the period's entries intact.
    step :run_pre_checks
    step :delete_existing_entries
    step :load_sqlite_db
    step :get_commitments
    step :run_formulas
    step :run_post_checks
    # On both tracks, so check results reach the report however the run ended.
    step :persist_check_results
    left :persist_check_results, id: :ensure_persist_check_results
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

      # In rare cases in Master fund formulas we need the feeder fund data
      fund_ids = if fund.json_fields["use_feeder_fund_data_in_formulas"].present? && fund.feeder_fund_ids.present?
                   ([fund_id] + fund.feeder_fund_ids).compact.uniq
                 else
                   [fund_id, master_fund_id].compact.uniq
                 end

      script_path = Rails.root.join("script/load_sqlite3_from_mysql.sh")

      # Define a unique temporary path for this run so concurrent runs stay isolated.
      # The fund ids alone are not unique enough: two runs of the *same* fund (parallel
      # cucumber processes all seed fund id 1, and two users can kick off the same fund
      # in production) would otherwise share one scratch file and clobber each other.
      # Development keeps the bare fund-id name so the "file already exists" shortcut
      # below can still reuse a previously loaded DB across runs.
      scratch_key = fund_ids.join("_")
      scratch_key = "#{scratch_key}_#{Process.pid}" unless Rails.env.development?

      # The scratch files run to several GB for a real fund, so they have to sit on real
      # disk. /tmp is a tmpfs on most dev machines: a tmpfs is backed by RAM+swap rather
      # than a device, so once memory is tight the import dies with "disk I/O error" while
      # df still reports free space. Rails.root/tmp is disk-backed and already gitignored.
      scratch_dir = ENV.fetch("ALLOCATION_SCRATCH_DIR", Rails.root.join("tmp/allocation").to_s)
      FileUtils.mkdir_p(scratch_dir)
      ctx[:sqlite_path] = File.join(scratch_dir, "irm_data_#{scratch_key}.sqlite3")

      # Extract the primary database configuration dynamically from ActiveRecord.
      # This ensures we use the correct credentials even in test/staging environments.
      db_config = ActiveRecord::Base.connection_db_config.configuration_hash
      adapter = db_config[:adapter].to_s

      # Prepare the environment variables required by the bash script
      env = {
        "FUND_IDS" => fund_ids.join(","),
        # Tell the script exactly which file to build. It would otherwise re-derive the
        # name from FUND_IDS alone and write somewhere we are not reading from.
        "SQLITE_DB" => ctx[:sqlite_path],
        # Keep the script's own intermediate TSVs beside our DB, off tmpfs
        "SCRATCH_DIR" => scratch_dir,
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

      # Everything the script was told to do, so a failure can be reproduced from the log
      # by hand without guessing at the environment. The password is deliberately omitted.
      Rails.logger.info do
        "load_sqlite_db: running #{script_path} for fund #{fund.id} (#{fund.name}) " \
          "fund_ids=#{fund_ids.join(',')} entity_id=#{entity_id} adapter=#{adapter} " \
          "source=#{env.fetch('SOURCE_SQLITE_DB', "#{env['MYSQL_HOST']}:#{env['MYSQL_PORT']}/#{env['MYSQL_DB']}")} " \
          "target=#{ctx[:sqlite_path]}"
      end

      # A load that cannot fit should say so before spending minutes exporting. Warn rather
      # than fail: we cannot know the required size up front, and a small fund fits anywhere.
      fs_type, free_mb = scratch_dir_stats(scratch_dir)
      Rails.logger.info { "load_sqlite_db: scratch dir #{scratch_dir} (fstype=#{fs_type || 'unknown'}, free=#{free_mb || '?'} MB)" }
      if fs_type == "tmpfs"
        notify("Allocation scratch dir #{scratch_dir} is RAM-backed (tmpfs) - a large fund may fail to load. Set ALLOCATION_SCRATCH_DIR to a disk path.", :warning, ctx[:user_id])
        Rails.logger.warn { "load_sqlite_db: #{scratch_dir} is a tmpfs; a large load can fail with 'disk I/O error' once RAM+swap are exhausted" }
      end

      # Execute the external migration script and wait for it to finish.
      # The script handles the heavy lifting of bulk exporting/importing via TSV.
      started_at = Time.zone.now
      status = nil
      if Rails.env.development? && File.exist?(ctx[:sqlite_path])
        Rails.logger.debug { "Skipping SQLite DB load in development as file already exists at #{ctx[:sqlite_path]}" }
        success = true
        script_output = ""
      else
        require "open3"
        script_output, status = Open3.capture2e(env, "bash #{script_path}")
        success = status.success?
      end
      duration = (Time.zone.now - started_at).round(1)

      # Log the script's whole output on every run, not just failures. It ends with a
      # per-table record count, which is the only way to tell a load that legitimately
      # found no rows from one that silently exported the wrong thing.
      Rails.logger.info do
        "load_sqlite_db: #{script_path.basename} exited #{status&.exitstatus || 0} after #{duration}s\n" \
          "----- script output -----\n#{script_output}----- end script output -----"
      end

      unless success
        exit_code = status&.exitstatus || "unknown"
        # Tail last 50 lines of output — the failure line is usually near the end.
        # The full output is in the log line above.
        tail_output = script_output.to_s.lines.last(50).join
        return load_failed(
          ctx,
          "Failed to load isolated SQLite DB for Entity ID: #{entity_id} " \
          "(fund_ids=#{fund_ids.join(',')}, adapter=#{adapter}, exit_code=#{exit_code}, " \
          "duration=#{duration}s, script=#{script_path})\nScript output:\n#{tail_output}",
          "Failed to load data for fund #{fund.name} (exit_code=#{exit_code}) — see the allocation run status for details"
        )
      end

      # A zero exit code is not proof of a usable DB — the file can be missing if the
      # script wrote somewhere else, so check before we hand the path to a connection pool.
      unless File.exist?(ctx[:sqlite_path])
        return load_failed(
          ctx,
          "Load script reported success but no SQLite DB exists at #{ctx[:sqlite_path]} " \
          "(fund_ids=#{fund_ids.join(',')}, entity_id=#{entity_id})",
          "Failed to load data for fund #{fund.name}: scratch database was not created"
        )
      end

      Rails.logger.debug { "Successfully loaded isolated SQLite DB for Entity ID: #{entity_id}" }

      # Clear any existing connection pool for this path to ensure we see the fresh file
      AccountEntryAllocation::WithScratchSqlite.disconnect_pool(ctx[:sqlite_path])

      # Reading the scratch DB is itself a failure point (missing table, unreadable file).
      # Without this rescue the exception escaped the operation and the run stopped with
      # no status recorded, which is what made this step look like it failed silently.
      begin
        with_scratch_sqlite(ctx[:sqlite_path]) do
          AccountEntrySqlite.where(allocation_run_id: ctx[:allocation_run_id]).delete_all
          entry_count = AccountEntrySqlite.where(fund_id: fund.id).count
          commitment_count = CapitalCommitmentSqlite.where(fund_id: fund.id).count
          db_size_mb = (File.size(ctx[:sqlite_path]) / 1024.0 / 1024.0).round(1)

          Rails.logger.info do
            "load_sqlite_db: loaded #{entry_count} account_entries and #{commitment_count} " \
              "capital_commitments for fund #{fund.id} (#{fund.name}) into #{ctx[:sqlite_path]} (#{db_size_mb} MB)"
          end

          # No commitments means every formula below will iterate an empty list and the run
          # produces nothing. That is almost always a setup problem (wrong fund, everything
          # dated after end_date), so say so loudly rather than reporting a silent success.
          if commitment_count.zero?
            warning = "No capital commitments were loaded for fund #{fund.id} (#{fund.name}) — " \
                      "the allocation will not generate any entries"
            Rails.logger.warn { "load_sqlite_db: #{warning}" }
            notify(warning, :warning, ctx[:user_id])
          end

          notify("Loaded #{entry_count} account entries and #{commitment_count} commitments for fund #{fund.name}", :info, ctx[:user_id])
        end
      rescue StandardError => e
        Rails.logger.error e.backtrace&.join("\n")
        return load_failed(
          ctx,
          "Loaded SQLite DB at #{ctx[:sqlite_path]} could not be read: #{e.class}: #{e.message}",
          "Failed to read loaded data for fund #{fund.name}: #{e.message}"
        )
      end

      true
    end

    # Filesystem type and free space (MB) for the scratch dir, or [nil, nil] if df is
    # unavailable. Used only for diagnostics, so any failure here is swallowed.
    def scratch_dir_stats(dir)
      row = `df -PTk #{Shellwords.escape(dir)} 2>/dev/null`.lines[1]
      return [nil, nil] if row.blank?

      fields = row.split
      [fields[1], fields[4].to_i / 1024]
    rescue StandardError
      [nil, nil]
    end

    # Single exit point for every load_sqlite_db failure.
    # Records the failure in all four places a failed run gets diagnosed from: the log, the
    # user's alert bar, ctx[:error] for the operation, and — the one that was missing — the
    # AllocationRun status. Without the status write, a failed load left the run sitting at
    # nil forever, so neither the UI nor a test could say what went wrong.
    def load_failed(ctx, error_msg, user_msg)
      Rails.logger.error { "load_sqlite_db: #{error_msg}" }
      notify(user_msg, :danger, ctx[:user_id])
      ctx[:error] = error_msg
      # Truncated: status is a display column, and error_msg can carry 50 lines of script output.
      ctx[:allocation_run]&.update_column(:status, error_msg.truncate(2000))
      false
    end

    def cleanup_sqlite(ctx, **)
      # Clean up the temporary isolated files from /tmp to keep the system lean.
      # The intermediate per-table TSVs are owned and removed by the load script itself
      # (it traps EXIT), so there is nothing to clean up for them here.
      sqlite_path = ctx[:sqlite_path]

      # First, disconnect the pool to close all file handles
      AccountEntryAllocation::WithScratchSqlite.disconnect_pool(sqlite_path) if sqlite_path

      [sqlite_path].compact.each do |path|
        if File.exist?(path)
          Rails.logger.debug { "Cleaning up isolated temporary file: #{path}" }
          File.delete(path) unless Rails.env.development?
        end

        # Also cleanup the sidecar files if they exist. `-journal` matters as much as the
        # WAL pair: the load script asks for journal_mode=OFF but SQLite falls back to
        # rollback-journal mode, so aborted runs were leaving orphan `-journal` files behind.
        [
          "#{path}-wal",
          "#{path}-shm",
          "#{path}-journal"
        ].each do |extra_path|
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
        commitments = commitments.includes(:fund)
        commitments = commitments.limit(3) if sample
        ctx[:commitments] = commitments.to_a # Load into memory since we'll be closing the connection
      end
      true
    end

    def run_formulas(ctx, **)
      return true unless ctx[:run_allocations]

      fund = ctx[:fund]
      ctx[:allocation_run].update_column(:status, "Pending")

      # Used to update the created account_entries. See CreateAccountEntry
      ctx[:form_type_id] = fund.entity.form_types.where(name: "AccountEntry").last
      ctx[:bulk_insert_records] = []

      # Loaded once as an array (not left as a lazy Relation) so this exact ordered
      # list -- and its indices -- are shared between the dependency scan below and
      # the execution loop further down; the two must agree on what "formula N" is.
      formula_list = get_formulas(ctx).to_a
      configure_commitment_cache_dependencies(ctx, formula_list)

      # Ensure that the portfolio_investments are up to date before running formulas. As this may compute the expenses for the portfolio investments
      fund.resave_portfolio_investments

      ctx[:formula_count] = formula_list.size

      # Mutex to ensure only one thread migrates from SQLite to Primary at a time
      ctx[:migration_mutex] = Thread::Mutex.new

      queue = Thread::Queue.new
      loader_thread = start_background_loader(ctx, queue)
      # Pass the queue to the main thread context, this is so heavy allocations can push to it
      # without having to pass it around everywhere.
      ctx[:queue] = queue

      with_scratch_sqlite(ctx[:sqlite_path]) do
        formula_list.each_with_index do |fund_formula, index|
          execute_formula(ctx, fund_formula, index)
          # Now that this formula has finished for every commitment, drop any cached
          # commitment field nothing later will read. See CommitmentCache#formula_completed.
          ctx[:commitment_cache].formula_completed(index)
          Rails.logger.info { "Completed formula #{index + 1} of #{formula_list.size}. Pushing to loader queue #{fund_formula.id}." }
          # Push the completed formula ID to the queue for parallel loading
          queue << fund_formula.id
        end
      ensure
        # Signal the loader thread to finish and wait for it
        queue << nil
        loader_thread&.join

        # Final catch-all: migrate any rows the background thread missed
        begin
          migrate_entries_to_primary(ctx, final_check: true)
        rescue StandardError => e
          error_message = "Final migration to primary DB failed: #{e.message}"
          Rails.logger.error error_message
          Rails.logger.error e.backtrace.join("\n")
          notify(error_message, :danger, ctx[:user_id])
          ctx[:allocation_run]&.update_column(:status, error_message)
          raise e
        end

        # We only set it to Success if it wasn't already set to an error message during formula execution
        # Reloading to check current DB state of the status
        ctx[:allocation_run].update_column(:status, "Success") if ctx[:allocation_run].reload.status == "Pending"
      end

      true
    end

    # Pre/post-run checks: FundFormulas with rule type PreRunCheck/PostRunCheck. Every check of the
    # kind runs even after one fails; any failure then stops the run, any warning only gets
    # recorded. See docs/business_requirements/allocation_run_checks.md.
    def run_pre_checks(ctx, **)
      ctx[:check_results] = []
      return true unless ctx[:run_allocations]

      run_checks(ctx, :pre)
    end

    def run_post_checks(ctx, **)
      return true unless ctx[:run_allocations]

      # run_formulas can return true with the run already failed: the background loader records
      # a migration error on the status and carries on rather than raising. Checking a ledger the
      # run never finished writing would only bury that error under check failures.
      status = ctx[:allocation_run]&.reload&.status
      if ctx[:allocation_run] && status != "Success"
        Rails.logger.warn { "run_post_checks: skipped for allocation run #{ctx[:allocation_run_id]}, status is #{status.inspect}" }
        return true
      end

      run_checks(ctx, :post)
    end

    # Stores the check results on the run's AllocationRunReport and queues the report build, but
    # only when a check failed or warned -- building the report is heavy aggregate SQL over
    # account_entries, not worth running for a clean run. Runs on the failure track too (see the
    # `left` wiring above), so it must never raise: a failure here would skip cleanup_sqlite.
    def persist_check_results(ctx, **)
      results = ctx[:check_results] || []
      flagged = results.select { |r| FLAGGED_CHECK_RESULTS.include?(r["result"]) }
      return true if flagged.empty?

      report = record_check_results(ctx, results)
      report_link = report && ActionController::Base.helpers.link_to("View the allocation run report", allocation_run_report_path(report),
                                                                     class: 'mb-1 badge bg-primary-subtle text-primary')

      if ctx[:check_failure_message]
        notify([ctx[:check_failure_message], report_link].compact.join("<br>"), :danger, ctx[:user_id])
      else
        warned = flagged.size
        notify(["#{warned} allocation #{'check'.pluralize(warned)} warned for #{ctx[:fund].name}", report_link].compact.join("<br>"), :warning, ctx[:user_id])
      end
      true
    rescue StandardError => e
      Rails.logger.error { "persist_check_results: failed for allocation run #{ctx[:allocation_run_id]}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}" }
      notify(ctx[:check_failure_message], :danger, ctx[:user_id]) if ctx[:check_failure_message]
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
                                                       # ISO, not l(end_date): this is a ransack filter value, not display text.
                                                       # Ransack casts it back with Date._parse, which always reads a slashed
                                                       # date as dd/mm/yyyy no matter the locale -- so an en-US "%m/%d/%Y"
                                                       # string like 08/07/2026 came back as 8 July and the link showed nothing.
                                                       ["reporting_date", :eq, end_date.to_fs(:db)],
                                                       [:entry_type, :eq, entry_type]
                                                     ])
        ActionController::Base.helpers.link_to(label, account_entries_path(fund_id: fund.id, filter: true, q: query_params), class: 'mb-1 badge  bg-primary-subtle text-primary', target: '_blank', rel: 'noopener')
      end.join

      # POST via data-turbo-method: this HTML is broadcast from a background job, not rendered
      # inside a real request, so a baked-in authenticity token (button_to) would not match the
      # viewer's session and the click would fail CSRF verification. Turbo reads the token live
      # from the page's own csrf-token meta tag when the link is clicked, so it works regardless
      # of where the markup was generated.
      check_run_link = ActionController::Base.helpers.link_to("Check This Allocation Run", allocation_run_reports_path(allocation_run_id: ctx[:allocation_run_id]),
                                                                class: 'mb-1 badge bg-primary-subtle text-primary', data: { turbo_method: :post })

      notify("#{msg}<br>#{links_html} #{check_run_link}", :success, user_id)
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
    def generate_soa(ctx, fund:, start_date:, end_date:, user_id:, template_id:, statement_for:, **)
      unless ctx[:generate_soa]
        Rails.logger.debug "Skipping Investor Statement generation"
        return true
      end

      begin
        msg = nil
        if statement_for.to_s.downcase == "investing entity"
          # investing_entity lvl / kyc level soa gen for each commitment
          KycLevelSoaGenJob.perform_now(commitment_ids: fund.capital_commitment_ids, template_id:, start_date: start_date.to_s, end_date: end_date.to_s, user_id:)
        else
          CapitalCommitmentSoaJob.perform_now(fund.id, nil, start_date.to_s, end_date.to_s, user_id, template_id:)
          msg = "Done generating Investor Statement for #{start_date} - #{end_date}"
        end
        Rails.logger.debug msg
        notify(msg, :success, user_id) if msg.present?
        true
      rescue Exception => e
        Rails.logger.error e.backtrace
        msg = "Error generating Investor Statement for #{start_date} - #{end_date}: #{e.message}"
        Rails.logger.error msg
        notify(msg, :danger, user_id)
        false
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
            error_message = "Migration to primary DB failed (formula #{fund_formula_id}): #{e.message}"
            Rails.logger.error error_message
            Rails.logger.error e.backtrace.join("\n")
            notify(error_message, :danger, ctx[:user_id])
            ctx[:allocation_run]&.update_column(:status, error_message)
            # Do not re-raise — keep the thread alive for remaining formulas.
            # The final migrate_entries_to_primary in the ensure block will retry unmigrated rows.
          end
        end
      end
    end

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
              if attrs["notes"].present? && attrs["notes"].length > 65_000
                # log this to a file for review
                Rails.logger.warn { "Truncating notes for AccountEntry SQLite ID #{sqlite_entry.id} during migration to primary DB" }
                attrs["notes"] = attrs["notes"].to_s.truncate(65_000)
              end
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
    # rubocop:enable Metrics/BlockLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    def relink_account_entry_parents(ctx)
      allocation_run_id = ctx[:allocation_run_id]
      return unless allocation_run_id

      msg = "Relinking AccountEntry parent relationships for allocation run #{allocation_run_id}"
      Rails.logger.debug { msg }
      notify(msg, :info, ctx[:user_id])

      # We use a direct SQL update to relink parents.
      # This joins the table on itself, matching the child's old parent_id (the id it had
      # in the scratch SQLite DB) with the parent's stored sqlite_id in the json_fields.
      #
      # The multi-table UPDATE ... INNER JOIN ... SET form is MySQL-only, and the test
      # suite runs on SQLite, so each dialect gets its own statement:
      #   * MySQL  — JSON_UNQUOTE(JSON_EXTRACT(...)) strips the quotes JSON_EXTRACT leaves
      #              on a string value; CAST(... AS UNSIGNED) compares against parent_id.
      #   * SQLite — UPDATE ... SET ... FROM (SQLite 3.33+). json_extract already returns
      #              an unquoted value here, and json_valid guards rows whose json_fields
      #              is not parseable JSON, which would otherwise abort the statement.
      sql = if AccountEntry.connection.adapter_name.downcase.include?("sqlite")
              <<~SQL.squish
                UPDATE account_entries AS child
                SET parent_id = parent.id
                FROM account_entries AS parent
                WHERE json_valid(parent.json_fields)
                  AND child.parent_id = CAST(JSON_EXTRACT(parent.json_fields, '$.sqlite_id') AS INTEGER)
                  AND parent.allocation_run_id = child.allocation_run_id
                  AND parent.entry_type = 'AccountEntry'
                  AND child.allocation_run_id = ?
                  AND child.parent_type = 'AccountEntry'
                  AND child.parent_id IS NOT NULL
              SQL
            else
              <<~SQL.squish
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
            end

      AccountEntry.connection.execute(AccountEntry.sanitize_sql_for_assignment([sql, allocation_run_id]))
    end

    # Pre/post-run checks write no entries, so they are kept out of the formula loop, the commitment
    # cache dependency scan and the delete-before-run scope, all of which read this list.
    def get_formulas(ctx)
      formulas_in_scope(ctx).without_run_checks
    end

    # The enabled checks of one kind, picked by the run's rule_for and tags exactly like formulas.
    def get_run_checks(ctx, kind)
      formulas_in_scope(ctx).where(rule_type: RunChecks::KINDS.fetch(kind))
    end

    def formulas_in_scope(ctx)
      fund     = ctx[:fund]
      rule_for = ctx[:rule_for]
      tag_list = ctx[:tag_list]

      formulas = FundFormula.enabled.where(fund_id: fund.id).order(sequence: :asc).includes(:fund, :entity)
      formulas = formulas.where(rule_for: rule_for) if rule_for.present?
      formulas = formulas.with_tags(tag_list.split(",")) if tag_list.present?
      formulas
    end

    # @return [Boolean] false when any check failed, which sends the operation down the failure track
    def run_checks(ctx, kind)
      checks = get_run_checks(ctx, kind).to_a
      return true if checks.empty?

      label = kind == :pre ? "Pre-run" : "Post-run"
      notify("Running #{checks.size} #{label.downcase} #{'check'.pluralize(checks.size)} for #{ctx[:fund].name}", :info, ctx[:user_id])

      results = RunChecks.new(checks, kind:, fund: ctx[:fund], start_date: ctx[:start_date],
                                      end_date: ctx[:end_date], allocation_run: ctx[:allocation_run]).call
      ctx[:check_results].concat(results)

      failed = results.select { |r| r["result"] == "fail" }
      return true if failed.empty?

      # Also the AllocationRun status, so it reads like every other failure: AllocationRunReport
      # check 1.1 and AllocationGroupRunJob both treat any status but Success as a failed run.
      message = "#{label} checks failed (#{failed.size}): " + failed.map { |r| "#{r['name']}: #{r['summary']}" }.join("; ")
      message = message.truncate(2000)
      Rails.logger.error { "run_checks: allocation run #{ctx[:allocation_run_id]} for fund #{ctx[:fund].id}: #{message}" }
      ctx[:allocation_run]&.update_column(:status, message)
      ctx[:error] = message
      ctx[:check_failure_message] = message
      false
    end

    # Merges this run's check results into its AllocationRunReport (creating it when the run has
    # none yet) and queues the report build. run_checks is kept apart from the report's own
    # findings: a rebuild recomputes findings from the ledger but cannot recompute check results,
    # which describe the data at the moment the run happened.
    # @return [AllocationRunReport, nil]
    def record_check_results(ctx, results)
      allocation_run = ctx[:allocation_run]
      return nil unless allocation_run

      report = AllocationRunReport.find_or_initialize_by(allocation_run:)
      report.assign_attributes(
        entity_id: allocation_run.entity_id,
        fund_id: allocation_run.fund_id,
        user_id: allocation_run.user_id,
        status: "Pending",
        message: nil,
        checked_at: nil,
        json_fields: (report.json_fields || {}).merge("run_checks" => results)
      )
      report.save!
      AllocationRunReportJob.perform_later(report.id)
      report
    end

    # Scans every in-scope formula's source (FundFormula#referenced_field_names) to
    # figure out which computed commitment fields are actually read by a later
    # formula, and the last formula sequence-position that reads each one.
    # CommitmentCache uses this to skip caching fields nothing reads, and to evict a
    # field once its last reader has run. formula_list must be the same ordered
    # array (and indices) used by the execution loop in #run_formulas.
    def configure_commitment_cache_dependencies(ctx, formula_list)
      referenced_field_names = Set.new
      last_consumer_index = {}

      formula_list.each_with_index do |formula, index|
        formula.referenced_field_names.each do |field_name|
          referenced_field_names << field_name
          # Iterating in ascending sequence order, so the last assignment for a
          # given name is always the highest (i.e. last) index that reads it.
          last_consumer_index[field_name] = index
        end
      end

      ctx[:commitment_cache].configure_dependencies(referenced_field_names, last_consumer_index)
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
