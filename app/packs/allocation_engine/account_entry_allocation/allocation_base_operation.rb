module AccountEntryAllocation
  class AllocationBaseOperation < Trailblazer::Operation
    # Set unconditionally for every formula by #create_instance_variables below, never by a
    # formula's own output -- FundFormulaDependencyGraph excludes these from "no producer"
    # broken-reference detection alongside CommitmentCache::BASE_FIELDS.
    ENGINE_PROVIDED_FIELDS = %w[fund start_date end_date].freeze

    # This method sets up all the variables required in a formula
    # It has to be called by the operation that is calling CreateAccountEntry
    # This is cause it passes its own bindings to CreateAccountEntry, and the formula is eval'ed using this binding
    # Hence all variables used in the formula must be setup before the binding is passed to CreateAccountEntry
    def create_instance_variables(ctx)
      # These are defaults which all Operations need
      @fund = ctx[:fund]
      @start_date = ctx[:start_date]
      @end_date = ctx[:end_date]

      # When a formula actually runs (see CreateAccountEntry) we store the results into ctx[:instance_variables]
      # For a formula "Setup Fees", we create a variable @setup_fees, set to the output of that formula.
      if ctx[:instance_variables].present?
        ctx[:instance_variables].each do |name, value|
          Rails.logger.debug { "CreateAccountEntry: @#{name} = #{value}" }
          instance_variable_set(:"@#{name}", value)
        end
      end
    end

    delegate :to_varable_name, to: :FundFormula

    def notify(message, level, user_id)
      UserAlert.new(user_id:, message:, level:).broadcast if user_id.present?
    end

    # rubocop:disable Security/Eval
    # rubocop:disable Lint/RescueException
    def safe_eval(eval_string, bdg)
      Rails.logger.debug { "AllocationBaseOperation: eval_string = #{eval_string}" }
      # Reject code-execution constructs before evaluating. eval_string is an interpolated fund
      # formula; guarding here protects the choke point even if the source formula bypassed
      # FundFormula#formula_kosher? at write time.
      result = eval(ApplicationRecord.safe_eval!(eval_string, context: "AllocationBaseOperation"), bdg, __FILE__, __LINE__)

      # SQLite silently stores Float::INFINITY and NaN but MySQL DECIMAL columns reject them,
      # causing the migration to primary DB to fail. Raise here with formula context instead.
      if result.respond_to?(:finite?) && !result.finite?
        kind = if result.nan?
                 "NaN"
               else
                 (result.positive? ? "Infinity" : "-Infinity")
               end
        raise ZeroDivisionError, "Formula produced #{kind} (divide-by-zero or 0.0/0.0). Formula: #{eval_string}"
      end

      result
    rescue SkipRule => e
      msg = "AllocationBaseOperation: SkipRule in eval #{eval_string}: #{e.message}"
      Rails.logger.error msg
      raise e
    rescue Exception => e
      # We should try and print out the variables used in the eval_string
      variables_used = ""
      begin
        FundFormula.new.interpolate_formula(eval_string:).each do |var|
          # var is a formula variable name; guard before eval-ing it in this debug/error path.
          variables_used += " #{var} = #{bdg.eval(ApplicationRecord.safe_eval!(var, context: 'AllocationBaseOperation var'))}, "
        end
      rescue Exception => e
        variables_used = "Error in getting variables used: #{e.message}"
      end

      msg = "AllocationBaseOperation: Error in eval #{eval_string}: #{e.message}. Variables used: #{variables_used}"
      Rails.logger.error msg
      raise msg
    end
    # rubocop:enable Lint/RescueException
    # rubocop:enable Security/Eval
  end
end
