class ApplicationRecordSqlite < ApplicationRecord
  self.abstract_class = true

  attribute :json_fields, :json, default: {}

  def custom_fields
    @cached_custom_fields ||= OpenStruct.new(json_fields)
    @cached_custom_fields
  end

  # 1. Establish a base connection to a dummy in-memory DB.
  # This provides a real ConnectionPool that Rails can use, but isolates us from MySQL.
  establish_connection(adapter: 'sqlite3', database: ':memory:')

  belongs_to :fund, class_name: 'FundSqlite'

  # 2. Patch the connection pool immediately after establishment.
  # We override the pool's `connection` method to intercept all requests.
  # This catches everything: Model.connection, Model.retrieve_connection, and internal Rails usage.
  class << connection_pool
    def connection
      if (thread_conn = Thread.current[:sqlite_scratch_connection])
        Rails.logger.debug { "#{self.class.name}: #{thread_conn.adapter_name}" }
        # Safety check
        raise "Safety Violation: Thread-local connection is not sqlite3!" unless thread_conn.adapter_name.downcase.include?('sqlite')

        return thread_conn
      end
      super
    end

    # Also override with_connection to ensure blocks use the correct connection.
    # We accept *args to remain compatible with whatever signature the base pool has.
    def with_connection(*args)
      if (thread_conn = Thread.current[:sqlite_scratch_connection])
        return yield(thread_conn)
      end

      super
    end
  end

  # We still override the class methods as a fallback/convenience,
  # though patching the pool should cover most cases.
  class << self
    delegate :connection, to: :connection_pool

    def retrieve_connection
      connection_pool.connection
    end
  end

  # Ensure inherited classes use the patched logic (mostly handled by sharing the pool)

  # Apply to existing constants if any
  %w[
    AccountEntrySqlite CapitalCommitmentSqlite PortfolioInvestmentSqlite
    AggregatePortfolioInvestmentSqlite InvestorSqlite FundSqlite
    FundUnitSettingSqlite FundUnitSqlite CapitalRemittanceSqlite
    CapitalRemittancePaymentSqlite CapitalDistributionPaymentSqlite
    CommitmentAdjustmentSqlite ExchangeRateSqlite
  ].each do |model_name|
    next unless Object.const_defined?(model_name)

    model = Object.const_get(model_name)
    # Force removal of any singleton methods that might bypass our logic
    class << model
      remove_method :connection if method_defined?(:connection, false)
      remove_method :retrieve_connection if method_defined?(:retrieve_connection, false)
    end
  end
end
