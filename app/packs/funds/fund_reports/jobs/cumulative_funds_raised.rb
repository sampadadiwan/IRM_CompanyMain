class CumulativeFundsRaised
  include CurrencyHelper

  def hash_tree
    Hash.new do |hash, key|
      hash[key] = hash_tree
    end
  end

  def generate_report(fund_id, start_date, end_date)
    Rails.logger.debug { "CumulativeFundsRaised: Generating Report for #{fund_id}, #{start_date}, #{end_date} " }

    @fund = Fund.find(fund_id)

    @fund_report = FundReport.find_or_initialize_by(name: "CumulativeFundsRaised", name_of_scheme: @fund.name, fund: @fund, entity_id: @fund.entity_id, start_date:, end_date:)

    data = hash_tree

    ########## Commitments, Remittances and Distributions

    data["Total Corpus As On Date"]["Value"] = @fund.collected_amount.to_d
    data["Total Commitments Raised (A1)"]["Value"] = @fund.capital_commitments.where(commitment_date: ..end_date).sum(:committed_amount_cents) / 100

    a2 = @fund.capital_remittance_payments.where(payment_date: ..start_date).sum(:amount_cents) / 100
    data["Funds Raised By The Scheme"]["At the beginning of the period (A2)"]["Value"] = a2

    b21 = @fund.capital_remittance_payments.where(payment_date: start_date..).where(payment_date: ..end_date).sum(:amount_cents) / 100
    data["Funds Raised By The Scheme"]["Additions during the period (B2)"]["Funds drawn from committed capital"]["Value"] = b21

    b22 = @fund.capital_distributions.where(distribution_date: start_date..).where(distribution_date: ..end_date).sum(:reinvestment_cents) / 100
    data["Funds Raised By The Scheme"]["Additions during the period (B2)"]["Reinvested Capital"]["Value"] = b22

    c2 = @fund.capital_distribution_payments.where(payment_date: start_date..).where(payment_date: ..end_date).sum(:amount_cents) / 100
    data["Funds Raised By The Scheme"]["Distributions during the period (C2)"]["Value"] = c2

    data["Funds Raised By The Scheme"]["At the end of the period (A2+B2)- (C2)"]["Value"] = a2 + b21 + b22 - c2

    ########## Investments

    a3 = @fund.portfolio_investments.buys.where(investment_date: ..start_date).sum { |pi| pi.net_quantity * pi.amount_cents / pi.quantity } / 100
    data["Investments made by the Scheme"]["At the beginning of the period (A3)"]["Value"] = a3.round(2)

    b3 = @fund.portfolio_investments.buys.where(investment_date: start_date..).where(investment_date: ..end_date).sum(:amount_cents) / 100
    data["Investments made by the Scheme"]["Additions during the period (B3)"]["Value"] = b3

    c3 = @fund.portfolio_investments.sells.where(investment_date: start_date..).where(investment_date: ..end_date).sum(:amount_cents) / 100

    data["Investments made by the Scheme"]["Divestment during the period (C3)"]["Value"] = c3.round(2)

    data["Investments made by the Scheme"]["At the end of the period (A3+B3)- (C3)"]["Value"] = (a3 + b3 - c3).round(2)

    ######### Save the report

    @fund_report.data = data
    @fund_report.save
  end
end
