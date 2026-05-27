class ApplicationRecordSqlite < ApplicationRecord
  self.abstract_class = true

  attribute :json_fields, :json, default: {}

  def custom_fields
    # Mirrors the WithCustomField concern's implementation. SQLite models (used by the
    # allocation engine) also expose custom_fields, so they get the same proxy wrapper
    # instead of OpenStruct to avoid the same per-record method-definition overhead.
    @cached_custom_fields ||= CustomFieldsProxy.new(json_fields)
  end

  # This is used to calculate the start of financial year based on the month offset set in models json fields
  def start_of_financial_year_date(end_date = nil, nil_if_not_set: false)
    # In some cases we may want to return nil if the end_date is not set and nil_if_not_set is true (See KpiCumulative)
    if end_date.nil? && nil_if_not_set
      nil
    else
      end_date ||= Time.zone.today
      # Some funds/entities/portcos want to set the start of the financial year to Jan some to April, this allows for that.
      month_offset_for_fy = json_fields && json_fields["month_offset_for_fy"].present? ? json_fields["month_offset_for_fy"].to_i : 3
      date = end_date.month > month_offset_for_fy ? end_date.beginning_of_year : (end_date.beginning_of_year - 1.year)
      (date + month_offset_for_fy.months)
    end
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
