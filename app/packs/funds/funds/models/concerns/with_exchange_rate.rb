module WithExchangeRate
  extend ActiveSupport::Concern

  def convert_currency(from, to, amount, as_of = nil)
    if to == from
      amount
    else
      @exchange_rate = exchange_rate(from, to, as_of)
      if @exchange_rate
        amount * @exchange_rate.rate
      else
        raise "Exchange rate from #{from} to #{to} not found."
      end
    end
  end

  def exchange_rate(from, to, as_of)
    exchange_rates = entity.exchange_rates.latest.where(from:, to:).order(as_of: :asc)
    @exchange_rate ||= as_of ? exchange_rates.where("as_of <= ?", as_of).last : exchange_rates.where(latest: true).last
    @exchange_rate
  end
end
