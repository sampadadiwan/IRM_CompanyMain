class CorpusDetailsJob
  include CurrencyHelper

  REPORT_NAME = "CorpusDetails".freeze
  TABLE_OFFSET = 2
  def hash_tree
    Hash.new do |hash, key|
      hash[key] = hash_tree
    end
  end

  def generate_report(fund_id, start_date, end_date)
    Rails.logger.debug { "Table 3: Generating Report for #{fund_id}, #{start_date}, #{end_date} " }

    @fund = Fund.find(fund_id)

    @fund_report = FundReport.find_or_initialize_by(name: REPORT_NAME, name_of_scheme: @fund.name, fund: @fund, entity_id: @fund.entity_id, start_date:, end_date:)

    data = hash_tree

    data["Name of Schema"]["Value"] = @fund.name
    data["Total Commitment received as at the end of quarter (Corpus) (Rs. Cr)"]["Value"] = money_to_currency(Money.new(@fund.capital_commitments.where("commitment_date <= ?", end_date).sum(&:committed_amount)))

    sum = 0
    @fund.capital_remittances.where("remittance_date <= ?", end_date).find_each do |cr|
      amt = cr.capital_remittance_payments.where("payment_date <= ?", end_date).sum(&:amount)
      sum += amt if amt.present?
    end
    data["Gross Cumulative Funds raised as at the end of quarter (Rs. Cr)"]["Value"] = money_to_currency(Money.new(sum)) # call amount or collected amount?

    data["Cumulative Portfolio Investments made as at the end of quarter(Rs. Cr)"]["Value"] = money_to_currency(Money.new(@fund.portfolio_investments.where("investment_date <= ?", end_date).where("quantity > 0").sum(&:amount)))
    data["Temporary investments made as at the end of quarter (Rs. Cr)"]["Value"] = ""
    data["Cash in hand as at the end of quarter (Rs. Cr.)"]["Value"] = ""
    data["Cumulative Cost of Divestment made as at the end of quarter (Rs. Cr)"]["Value"] = money_to_currency(Money.new(@fund.portfolio_investments.where("investment_date <= ?", end_date).sum(&:cost_of_sold)&.abs))
    data["Cumulative Principal/ Capital Distributions made to the investors as at the end of quarter (Rs. Cr)"]["Value"] = money_to_currency(Money.new(@fund.capital_distributions.where("distribution_date <= ?", end_date).sum(&:cost_of_investment)))

    ######### Save the report

    @fund_report.data = data
    @fund_report.save!
  end

  def generate_excel_report(fund_id, _start_date, end_date, excel, single: false)
    primary_fund = Fund.find(fund_id)

    sheet = excel.worksheet(FundReportJob::REPORT_TO_SHEET[REPORT_NAME])

    funds = primary_fund.entity.funds
    funds = funds.where(id: fund_id) if single

    funds.each_with_index do |fund, index|
      row_index = index + TABLE_OFFSET
      sr_no = index + 1
      name_of_scheme = fund.name
      Rails.logger.debug { "CorpusDetails for #{name_of_scheme}" }
      total_commitment_received = Money.new(fund.capital_commitments.where("commitment_date <= ?", end_date).sum(&:committed_amount)).amount.to_d
      sum = 0
      fund.capital_remittances.where("remittance_date <= ?", end_date).find_each do |cr|
        amt = cr.capital_remittance_payments.where("payment_date <= ?", end_date).sum(&:amount)
        sum += amt if amt.present?
      end
      gross_cumulative_funds_raised = Money.new(sum).amount.to_d
      cumulative_portfolio_investments = Money.new(fund.portfolio_investments.where("investment_date <= ?", end_date).where("quantity > 0").sum(&:amount)).amount.to_d
      temporary_investments_made = ""
      cash_in_hand = ""
      cumulative_cost_of_divestment = Money.new(fund.portfolio_investments.where("investment_date <= ?", end_date).sum(&:cost_of_sold)&.abs).amount.to_d
      cumulative_principal_capital_distributions = Money.new(fund.capital_distributions.where("distribution_date <= ?", end_date).sum(&:cost_of_investment)).amount.to_d
      row_data = [sr_no, name_of_scheme, total_commitment_received, gross_cumulative_funds_raised, cumulative_portfolio_investments, temporary_investments_made, cash_in_hand, cumulative_cost_of_divestment, cumulative_principal_capital_distributions]
      if index.zero?
        sheet.update_row(row_index, *row_data)
      else
        sheet.insert_row(row_index, row_data)
      end
    end
    excel
  end
end
