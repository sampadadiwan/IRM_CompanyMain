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

    # SQL that changes scratch data. Matched at the start of the statement only, so testing a
    # multi-megabyte bulk INSERT costs nothing.
    SCRATCH_WRITE_SQL = /\A\s*(INSERT|UPDATE|DELETE|REPLACE)\b/i

    # Rails empties its query cache when a write goes through a connection it knows about. The scratch
    # pool is hand-built (WithScratchSqlite) and Rails does not know about it, so a write would leave
    # cached reads behind: a later formula would be handed sums that miss the entries just inserted.
    # This subscriber tells the cache: after any write on the current thread's scratch connection, that
    # thread's cache is emptied (clear_query_cache only touches the calling thread's store, so another
    # thread's cache is never affected). A cached read can therefore never outlive a write, even if a
    # write is added inside a cached block later.
    def self.guard_scratch_query_cache_against_writes
      @guard_scratch_query_cache_against_writes ||= ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        connection = Thread.current[:sqlite_scratch_connection]
        next unless connection && payload[:connection].equal?(connection)

        connection.pool.clear_query_cache if payload[:sql].match?(SCRATCH_WRITE_SQL)
      end
    end
    guard_scratch_query_cache_against_writes

    # Runs the block with the query cache on for the scratch SQLite connection, when asked to and
    # when one is active (it always is during a run). Reads elsewhere (MySQL) are unaffected.
    #
    # The cache is also emptied on the way in and out, so it never outlives the block, and any write
    # on the scratch connection empties it at once (see the guard above). The two places that use it
    # only read, so in practice the guard never fires.
    #
    # Inside an enclosing cached block the cache is already on and the outer block owns the
    # clearing, so the inner one just runs.
    def with_scratch_query_cache(enabled: true, &)
      scratch_connection = Thread.current[:sqlite_scratch_connection]
      return yield unless enabled && scratch_connection
      return yield if scratch_connection.query_cache_enabled

      scratch_connection.pool.clear_query_cache
      begin
        scratch_connection.cache(&)
      ensure
        scratch_connection.pool.clear_query_cache
      end
    end

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
