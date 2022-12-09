module FundCalcs
  extend ActiveSupport::Concern

  def compute_rvpi
    valuation = valuations.order(valuation_date: :asc).last
    (valuation.pre_money_valuation_cents / collected_amount_cents).round(2) if valuation
  end

  def compute_dpi
    (distribution_amount_cents / collected_amount_cents).round(2) if collected_amount_cents.positive?
  end

  def compute_tvpi
    dpi + rvpi if rvpi && dpi
  end

  def compute_moic
    # (self.tvpi / self.collected_amount_cents).round(2) if self.tvpi && self.collected_amount_cents > 0
  end

  def compute_xirr
    last_valuation = valuations.last
    if last_valuation

      cf = Xirr::Cashflow.new

      capital_calls.each do |capital_call|
        cf << Xirr::Transaction.new(-1 * capital_call.collected_amount_cents, date: capital_call.due_date)
      end

      capital_distributions.each do |capital_distribution|
        cf << Xirr::Transaction.new(capital_distribution.net_amount_cents, date: capital_distribution.distribution_date)
      end

      cf << Xirr::Transaction.new(last_valuation.pre_money_valuation_cents, date: last_valuation.valuation_date)

      Rails.logger.debug { "fund.xirr cf: #{cf}" }
      Rails.logger.debug { "fund.xirr irr: #{cf.xirr}" }
      (cf.xirr * 100).round(2)

    end
  end
end
