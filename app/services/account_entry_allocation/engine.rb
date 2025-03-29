# app/concepts/account_entry_allocation/engine.rb

module AccountEntryAllocation
  # This class can serve as a simple "facade" or orchestrator to run
  # your entire allocation sequence, calling the sub-operations in order.
  class Engine
    attr_accessor :fund, :start_date, :end_date, :user_id, :rule_for, :tag_list,
                  :run_allocations, :explain, :generate_soa, :template_id, :fund_ratios,
                  :sample, :allocation_run_id, :allocation_run, :formula_count, :formula_index

    def initialize(fund, start_date, end_date, user_id: nil, rule_for: nil, tag_list: nil,
                   run_allocations: true, explain: false, generate_soa: false,
                   template_id: nil, fund_ratios: false, sample: false, allocation_run_id: nil)
      @fund            = fund
      @start_date      = start_date
      @end_date        = end_date
      @user_id         = user_id
      @rule_for        = rule_for
      @tag_list        = tag_list
      @run_allocations = run_allocations
      @explain         = explain
      @generate_soa    = generate_soa
      @template_id     = template_id
      @fund_ratios     = fund_ratios
      @sample          = sample
      @allocation_run_id = allocation_run_id

      # Possibly retrieve an AllocationRun record
      @allocation_run = AllocationRun.find(allocation_run_id) if allocation_run_id.present?
    end

    # Here we demonstrate a single "call" method that triggers the main operation,
    # which then calls sub-operations for each piece of logic.
    # You can adapt as needed.
    def call
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
        template_id: template_id,
        fund_ratios: fund_ratios,
        sample: sample,
        allocation_run_id: allocation_run_id,
        allocation_run: allocation_run,
        bulk_insert_records: [],
        formula_count: 0,
        formula_index: 0,
        commitment_cache: @commitment_cache,
        instance_variables: @instance_variables
      }
      Rails.logger.debug { "Engine: ctx = #{ctx}" }
      # Now call the RunFormulas operation (which in turn calls sub-operations).
      AccountEntryAllocation::RunFormulas.call(ctx)

      # Return the final context or the result object for further inspection.
    end

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
