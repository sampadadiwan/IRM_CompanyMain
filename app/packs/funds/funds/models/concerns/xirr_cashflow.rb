# Expands [Array] to store a set of transactions which will be used to calculate the XIRR
# @note A Cashflow should consist of at least two transactions, one positive and one negative.
class XirrCashflow < Array
  PERIOD = 365.25
  FALLBACK = true

  attr_reader :raise_exception, :fallback, :iteration_limit, :options

  # @param args [Transaction]
  # @example Creating a Cashflow
  #   cf = Cashflow.new
  #   cf << Transaction.new( 1000, date: '2013-01-01'.to_date)
  #   cf << Transaction.new(-1234, date: '2013-03-31'.to_date)
  #   Or
  #   cf = Cashflow.new Transaction.new( 1000, date: '2013-01-01'.to_date), Transaction.new(-1234, date: '2013-03-31'.to_date)
  def initialize(flow: [], period: PERIOD, ** options)
    super() # Ensures the Array parent class initializes properly
    @period   = period
    @fallback = options[:fallback] || FALLBACK
    @options  = options
    self << flow
    flatten!
  end

  # Check if Cashflow is invalid
  # @return [Boolean]
  def invalid?
    inflow.empty? || outflows.empty?
  end

  # Inverse of #invalid?
  # @return [Boolean]
  def valid?
    !invalid?
  end

  # @return [Float]
  # Sums all amounts in a cashflow
  def sum
    sum(&:amount)
  end

  # Last investment date
  # @return [Time]
  def max_date
    @max_date ||= map(&:date).max
  end

  # First investment date
  # @return [Time]
  def min_date
    @min_date ||= map(&:date).min
  end

  # @return [String]
  # Error message depending on the missing transaction
  def invalid_message
    return 'No positive transaction' if inflow.empty?

    'No negative transaction' if outflows.empty?
  end

  def period
    @temporary_period || @period
  end

  # rubocop:disable Performance/CompareWithBlock
  def <<(arg)
    super
    sort! { |x, y| x.date <=> y.date }
    self
  end
  # rubocop:enable Performance/CompareWithBlock
end
