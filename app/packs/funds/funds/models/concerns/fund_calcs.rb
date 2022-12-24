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

      capital_remittances.each do |cr|
        cf << Xirr::Transaction.new(-1 * cr.collected_amount_cents, date: cr.payment_date)
      end

      capital_distribution_payments.each do |cdp|
        cf << Xirr::Transaction.new(cdp.amount_cents, date: cdp.payment_date)
      end

      cf << Xirr::Transaction.new(last_valuation.pre_money_valuation_cents, date: last_valuation.valuation_date)

      Rails.logger.debug { "fund.xirr cf: #{cf}" }
      Rails.logger.debug { "fund.xirr irr: #{cf.xirr}" }
      (cf.xirr * 100).round(2)

    end
  end
end
