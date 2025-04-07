class CashFlowJob
  include CurrencyHelper

  REPORT_NAME = "CashFlow".freeze
  TABLE_OFFSET = 3

  def hash_tree
    Hash.new do |hash, key|
      hash[key] = hash_tree
    end
  end

  def generate_report(fund_id, start_date, end_date)
    Rails.logger.debug { "Generating CashFlow Report for #{fund_id}, #{start_date}, #{end_date} " }

    @fund = Fund.includes(:capital_commitments).find(fund_id)
    @end_date = end_date

    @fund_report = FundReport.find_or_initialize_by(name: REPORT_NAME, name_of_scheme: @fund.name, fund: @fund, entity_id: @fund.entity_id, start_date: start_date, end_date: end_date)

    data = hash_tree

    data.merge!(table_data(@fund))

    ######### Save the report
    @fund_report.data = data
    @fund_report.save!
  end

  def generate_excel_report(fund_id, _start_date, end_date, workbook, single: false)
    fund = Fund.find(fund_id)
    @end_date = end_date

    sheet1 = workbook[CrisilReportJob::REPORT_TO_SHEET[REPORT_NAME]]

    funds = fund.entity.funds
    funds = funds.where(id: fund_id) if single
    row_idx = TABLE_OFFSET
    funds.each do |scheme|
      scheme_name = scheme.name
      Rails.logger.debug { "CashFlows for #{scheme_name}" }
      rows = get_row_data(scheme)
      rows.each do |row_data|
        Rails.logger.debug row_data
        next if row_data.blank?

        row_data.each_with_index do |data, column_idx|
          next if data.blank?

          style_index = sheet1[3][column_idx].style_index # copy style from top cell
          sheet1.add_cell(row_idx, column_idx, data)
          sheet1[row_idx][column_idx].style_index = style_index
        end
        row_idx += 1
      end
    end
    workbook
  end

  def table_data(fund)
    data = hash_tree
    fund.capital_remittance_payments.where(payment_date: ..@end_date).select("payment_date, SUM(amount_cents) as total_cash_flow").group(:payment_date).order(:payment_date).each do |rem_payment|
      data[rem_payment.payment_date.strftime("%d-%m-%Y")]["Remittance Payments Cash Flow"]["Value"] = (rem_payment.total_cash_flow / 100.0) / 1_000_000.0
    end
    # non_inr_remit_amounts = {}
    # fund.capital_remittance_payments.where(payment_date: ..@end_date).order(:payment_date).each do |rem_payment|
    #   payment_date = rem_payment.payment_date.strftime("%d-%m-%Y")
    #   non_inr_remit_amounts[payment_date] ||= 0
    #   non_inr_remit_amounts[payment_date] += rem_payment.folio_amount_cents if rem_payment.folio_amount.currency != "INR"
    # end
    # non_inr_remit_amounts.each do |payment_date, amount|
    #   data[payment_date]["Non INR Remittance Payments Cash Flow"]["Value"] = (amount / 100.0) / 1_000_000.0
    # end
    # fund.capital_distribution_payments.where(payment_date: ..@end_date).select("payment_date, SUM(gross_payable_cents) as total_cash_flow").group(:payment_date).order(:payment_date).each do |dist_payment|
    #   data[dist_payment.payment_date.strftime("%d-%m-%Y")]["Distribution Payments Cash Flow"]["Value"] = (dist_payment.total_cash_flow / 100.0) / 1_000_000.0
    # end

    # non_inr_dist_amounts = {}
    # fund.capital_distribution_payments.where(payment_date: ..@end_date).order(:payment_date).each do |dist_payment|
    #   payment_date = dist_payment.payment_date.strftime("%d-%m-%Y")
    #   non_inr_dist_amounts[payment_date] ||= 0
    #   non_inr_dist_amounts[payment_date] += dist_payment.folio_amount_cents if dist_payment.folio_amount.currency != "INR"
    # end
    # non_inr_dist_amounts.each do |payment_date, amount|
    #   data[payment_date]["Non INR Distribution Payments Cash Flow"]["Value"] = (amount / 100.0) / 1_000_000.0
    # end

    fund.capital_distribution_payments.order(:payment_date).each do |dist_payment|
      payment_date = dist_payment.payment_date.strftime("%d-%m-%Y")
      principle_repayment = (dist_payment.cost_of_investment_with_fees_cents / 100.0) / 1_000_000.0
      income_distribution = ((dist_payment.gross_payable_cents - dist_payment.cost_of_investment_with_fees_cents) / 100.0) / 1_000_000.0
      # convert to inr
      # Initialize the date in results hash
      data[payment_date] ||= []
      if income_distribution.positive?
        if data.dig(payment_date, "Distribution Payments Cash Flow", "Income Distribution", "Value").blank?
          data[payment_date]["Distribution Payments Cash Flow"]["Income Distribution"]["Value"] = income_distribution
        else
          data[payment_date]["Distribution Payments Cash Flow"]["Income Distribution"]["Value"] += income_distribution
        end
      end
      if principle_repayment.positive?
        if data.dig(payment_date, "Distribution Payments Cash Flow", "Principal Repayment", "Value").blank?
          data[payment_date]["Distribution Payments Cash Flow"]["Principal Repayment"]["Value"] = principle_repayment
        else
          data[payment_date]["Distribution Payments Cash Flow"]["Principal Repayment"]["Value"] += principle_repayment
        end
      end
    end
    data.sort_by { |key, _| Date.strptime(key, "%d-%m-%Y") }.to_h
  end

  def get_row_data(fund)
    scheme_name = fund.name
    rows = []
    data = table_data(fund)
    data.each do |date, values|
      if values["Remittance Payments Cash Flow"]["Value"].present?
        row = []
        row << Date.parse(date).strftime("%d-%b-%y")
        row << scheme_name
        row << ""
        row << values["Remittance Payments Cash Flow"]["Value"]
        row << "Capital drawdown"
        row << values["Non INR Remittance Payments Cash Flow"]["Value"]
        rows << row
      end
      # next if values["Distribution Payments Cash Flow"]["Value"].blank?

      # row = []
      # row << Date.parse(date).strftime("%d-%b-%y")
      # row << scheme_name
      # row << ""
      # row << values["Distribution Payments Cash Flow"]["Value"]
      # row << "Income distribution (pre-tax, pre-carry)"
      # row << values["Non INR Distribution Payments Cash Flow"]["Value"]
      # rows << row

      if values["Distribution Payments Cash Flow"]["Income Distribution"]["Value"].present?
        row = []
        row << Date.parse(date).strftime("%d-%b-%y")
        row << scheme_name
        row << ""
        row << values["Distribution Payments Cash Flow"]["Income Distribution"]["Value"]
        row << "Income distribution (pre-tax, pre-carry)"
        row << ""
        rows << row
      end
      next if values["Distribution Payments Cash Flow"]["Principal Repayment"]["Value"].blank?

      row = []
      row << Date.parse(date).strftime("%d-%b-%y")
      row << scheme_name
      row << ""
      row << values["Distribution Payments Cash Flow"]["Principal Repayment"]["Value"]
      row << "Principal repayment"
      row << ""
      rows << row
    end
    rows
  end
end
