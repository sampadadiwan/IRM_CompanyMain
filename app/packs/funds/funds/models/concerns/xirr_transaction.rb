# A unit of the Cashflow.
class XirrTransaction
  attr_reader :amount, :date, :notes

  # @example
  #   Transaction.new -1000, date: Date.now
  # @param amount [Numeric]
  # @param opts [Hash]
  # @note Don't forget to add date: [Date] in the opts hash.
  def initialize(amount, opts = {})
    self.amount = amount

    # Set optional attributes..
    opts.each do |key, value|
      send(:"#{key}=", value)
    end
  end

  # Sets the date
  # @param value [Date, Time]
  # @return [Date]
  def date=(value)
    @date = value.is_a?(Time) ? value.to_date : value
  end

  # Sets the amount
  # @param value [Numeric]
  # @return [Float]
  def amount=(value)
    @amount = value.to_f
  rescue StandardError
    @amount = 0.0
  end

  def notes=(value)
    @notes = value.to_s
  end

  # @return [String]
  def inspect
    "T(#{@amount},#{@date}, #{@notes})"
  end
end
