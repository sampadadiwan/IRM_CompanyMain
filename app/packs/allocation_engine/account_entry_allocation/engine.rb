# Each Folio within an AIF can have AccountEntries, which are calculated.
# The logic for these calculations comes from FundFormulas — each of which contains a snippet of code (probably stored as a string or block) that’s evaluated dynamically.
# There is a FundFormulaEngine, which:
## Iterates over each Folio.
## Fetches the relevant data for that folio from the database.
## Evals the FundFormula code using that data.
## Produces an amount.
## Creates an AccountEntry for the folio using this calculated amount.
# So essentially: Dynamic calculation logic (via FundFormulas) + Per-folio context → AccountEntry

module AccountEntryAllocation
  # This class can serve as a simple "facade" or orchestrator to run
  # your entire allocation sequence, calling the sub-operations in order.
  class Engine
    attr_accessor :fund, :start_date, :end_date, :user_id, :rule_for, :tag_list,
                  :run_allocations, :explain, :generate_soa, :statement_for, :template_id, :fund_ratios,
                  :sample, :allocation_run_id, :allocation_run, :formula_count, :formula_index

    def initialize(fund, start_date, end_date, user_id: nil, rule_for: nil, tag_list: nil,
                   run_allocations: true, explain: false, generate_soa: false, statement_for: "commitment",
                   template_id: nil, fund_ratios: false, sample: false, allocation_run_id: nil, timing: false)
      @fund            = fund
      @start_date      = start_date
      @end_date        = end_date
      @user_id         = user_id
      @rule_for        = rule_for
      @tag_list        = tag_list
      @run_allocations = run_allocations
      @explain         = explain
      @generate_soa    = generate_soa
      @statement_for   = statement_for
      @template_id     = template_id
      @fund_ratios     = fund_ratios
      @sample          = sample
      @allocation_run_id = allocation_run_id
      @timing = timing

      # Possibly retrieve an AllocationRun record
      @allocation_run = AllocationRun.find(allocation_run_id) if allocation_run_id.present?
    end

    # What call returns when the run was refused before any formula ran. Quacks like the Trailblazer
    # result for the two things callers read (AllocationGroupRunJob): failure? and [:error].
    Refused = Struct.new(:error) do
      def failure? = true
      def success? = false
      def [](key) = key == :error ? error : nil
    end

    # Every way into the engine (the allocate screen's job, run groups, statement generation,
    # rerun!, the console) comes through here, so this is where "one run per fund at a time" is
    # enforced for real: the AllocationRun validation stops a second run being created, and the
    # fund lock stops two engines that slipped past it (a double-click) from running together.
    def call
      AllocationFundLock.hold(fund.id) do |taken|
        # Another engine is running on this fund right now (on any thread, process or box)
        next refuse("Not started: another allocation run is already running on this fund. Wait for it to finish, then run this period again.") unless taken
        # Checked after taking the lock, so a user marking the run crashed and the job starting
        # cannot both slip through: the run was marked while its job sat in the queue
        next refuse(nil) if allocation_run&.reload&.crashed_by_user?

        run_operation
      end
    end

    private

    # Records why the run did not start (unless the status already says so) and tells the user
    def refuse(message)
      Rails.logger.warn { "Engine: allocation run #{allocation_run_id} for fund #{fund.id} not started: #{message || allocation_run&.status}" }
      allocation_run&.update_column(:status, message) if message
      UserAlert.new(user_id:, message: message || allocation_run.status, level: :danger).broadcast if user_id
      Refused.new(message || allocation_run&.status)
    end

    def run_operation
      # Build a shared context. In Trailblazer, this is the `ctx` hash.
      @instance_variables = {}
      @commitment_cache = AccountEntryAllocation::CommitmentCache.new(self)

      ctx = {
        fund: fund,
        start_date: start_date,
        end_date: end_date,
        user_id: user_id,
        rule_for: rule_for,
        tag_list: tag_list,
        run_allocations: run_allocations,
        explain: explain,
        generate_soa: generate_soa,
        statement_for: statement_for,
        template_id: template_id,
        fund_ratios: fund_ratios,
        sample: sample,
        allocation_run_id: allocation_run_id,
        allocation_run: allocation_run,
        bulk_insert_records: [],
        formula_count: 0,
        formula_index: 0,
        commitment_cache: @commitment_cache,
        instance_variables: @instance_variables,
        timing: @timing
      }
      Rails.logger.debug { "Engine: ctx = #{ctx}" }

      # Start tracing just your Fund query:
      # SqlTracer.start(pattern: /FROM `investor_kycs`/)
      # Now call the RunFormulas operation (which in turn calls sub-operations).
      result = AccountEntryAllocation::RunFormulas.wtf?(ctx)
      # SqlTracer.stop

      # The operation's result used to be discarded, so a failed run was indistinguishable
      # from a successful one here: the job finished normally and the AllocationRun was left
      # at whatever status the failing step happened to set -- nil, if it set none.
      # Backstop it, without overwriting a more specific message a deeper step already wrote.
      if result.failure?
        # Read through the result, not the local ctx hash: Trailblazer wraps the hash we
        # passed in, so anything a step writes to its ctx never lands back on that hash.
        error = result[:error].presence || "Allocation run failed - see the log for the failing step"
        Rails.logger.error { "Engine: allocation run #{allocation_run_id} for fund #{fund&.id} failed: #{error}" }
        allocation_run.update_column(:status, error.to_s.truncate(2000)) if allocation_run && allocation_run.reload.status.blank?
      elsif allocation_run && allocation_run.reload.status.blank?
        # A run that ran no formulas (statements / ratios only) never writes a status of its own. Left
        # blank it would read as still running, and block the fund (AllocationRun.unfinished).
        allocation_run.update_column(:status, "Success")
      end

      # Return the final context or the result object for further inspection.
      result
    rescue StandardError => e
      # An exception ends the run in this process: record it, or the run reads as still running and
      # blocks the fund until someone marks it crashed. A more specific status a step wrote is kept.
      unfinished = allocation_run && AllocationRun::UNFINISHED_STATUSES.include?(allocation_run.reload.status)
      allocation_run.update_column(:status, "Failed: #{e.class}: #{e.message}".truncate(2000)) if unfinished
      raise
    end

    public

    def create_variables(cached_commitment_fields)
      # Create variables available to eval here from all the cached fields
      # This is what allows formulas to have things line @cash_in_hand or @units
      cached_commitment_fields.keys.sort.each do |f|
        # variable names cannot be created with special chars - so delete them
        variable_name = f.delete('.&:')
        # In the new refactored version, we store these in a hash, and convert them to instance variables in CreateAccountEntry
        @instance_variables[variable_name] = cached_commitment_fields[f]
        # Rails.logger.debug { "Engine: @#{variable_name} to #{cached_commitment_fields[f]}" }
      end
    end
  end
end
