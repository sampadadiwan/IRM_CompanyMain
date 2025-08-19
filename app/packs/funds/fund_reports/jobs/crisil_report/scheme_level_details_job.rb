class SchemeLevelDetailsJob
  include CurrencyHelper

  REPORT_NAME = "SchemeLevelDetails".freeze
  TABLE_OFFSET = 3
  CRISIL_CATEGORY = {
    "Banks" => "Institutional",
    "NBFCs" => "Institutional",
    "Insurance Companies" => "Institutional",
    "Pension Funds" => "Institutional",
    "Provident Funds" => "Institutional",
    "AIFs" => "Institutional",
    "FPIs" => "Institutional",
    "FVCIs" => "Institutional",
    "Foreign Others" => "Institutional",
    "Employee Benefit Trust of Manager" => "Institutional",
    "Domestic Developmental Agencies/Government Agencies" => "Institutional",
    "Others" => "Institutional",
    "Other Corporates" => "Retail",
    "Resident Individuals" => "Retail",
    "Non-Corporate (other than Trusts)" => "Retail",
    "Trusts" => "Retail",
    "NRIs" => "Retail",
    "Sponsor" => "Retail",
    "Manager" => "Retail",
    "Directors/Partners/Employees of Sponsor" => "Retail",
    "Directors/Partners/Employees of Manager" => "Retail"
  }.freeze

  FIRST_CLOSE_NAME = "First Close".freeze
  FINAL_CLOSE_NAME = "Final Close".freeze

  def hash_tree
    Hash.new do |hash, key|
      hash[key] = hash_tree
    end
  end

  def generate_report(fund_id, start_date, end_date)
    Rails.logger.debug { "Generating SchemeLevelDetails Report for #{fund_id}, #{start_date}, #{end_date} " }

    @fund = Fund.includes(:capital_commitments).find(fund_id)
    @end_date = end_date
    @institutional_categories = CRISIL_CATEGORY.select { |_, v| v == "Institutional" }.keys
    @retail_categories = CRISIL_CATEGORY.select { |_, v| v == "Retail" }.keys
    @fund_report = FundReport.find_or_initialize_by(name: REPORT_NAME, name_of_scheme: @fund.name, fund: @fund, entity_id: @fund.entity_id, start_date:, end_date:)

    @fund_report = FundReport.find_or_initialize_by(name: REPORT_NAME, name_of_scheme: @fund.name, fund: @fund, entity_id: @fund.entity_id, start_date: start_date, end_date: end_date)

    commitments = @fund.capital_commitments.where(commitment_date: ..end_date)
    json_method = Rails.env.test? ? "json_extract" : "JSON_UNQUOTE"

    @institutional_kyc_commitments = commitments
                                     .joins(:investor_kyc)
                                     .where("#{json_method}(investor_kycs.json_fields -> '$.sebi_investor_sub_category') IN (?)", @institutional_categories)
                                     .where(commitment_date: ..end_date)

    @retail_kyc_commitments = commitments
                              .joins(:investor_kyc)
                              .where("#{json_method}(investor_kycs.json_fields -> '$.sebi_investor_sub_category') IN (?)", @retail_categories)
                              .where(commitment_date: ..end_date)

    ######### Save the report
    @fund_report.data = data
    @fund_report.save!
  end

  # rubocop:disable Metrics/MethodLength
  def generate_excel_report(fund_id, _start_date, end_date, workbook, single: false)
    fund = Fund.find(fund_id)
    @end_date = end_date
    @institutional_categories = CRISIL_CATEGORY.select { |_, v| v == "Institutional" }.keys
    @retail_categories = CRISIL_CATEGORY.select { |_, v| v == "Retail" }.keys
    sheet1 = workbook[CrisilReportJob::REPORT_TO_SHEET[REPORT_NAME]]

    funds = fund.entity.funds
    funds = funds.where(id: fund_id) if single
    row_idx = TABLE_OFFSET + 1
    funds.each do |scheme|
      scheme_name = scheme.name
      commitments = scheme.capital_commitments.includes(:investor_kyc).where(commitment_date: ..end_date)
      json_method = Rails.env.test? ? "json_extract" : "JSON_UNQUOTE"
      institutional_kyc_commitments = commitments
                                      .joins(:investor_kyc)
                                      .where("#{json_method}(investor_kycs.json_fields -> '$.sebi_investor_sub_category') IN (?)", @institutional_categories)
                                      .where(commitment_date: ..end_date)

      retail_kyc_commitments = commitments
                               .joins(:investor_kyc)
                               .where("#{json_method}(investor_kycs.json_fields -> '$.sebi_investor_sub_category') IN (?)", @retail_categories)
                               .where(commitment_date: ..end_date)
      Rails.logger.debug { "SchemeLevelDetails for #{scheme_name}" }
      institutional_and_retial_row_data = get_row_data(scheme, institutional_kyc_commitments, retail_kyc_commitments)
      institutional_and_retial_row_data.each do |row_data|
        Rails.logger.debug row_data
        next if row_data.blank?

        row_data.each_with_index do |data, column_idx|
          next if data.blank?

          style_index = sheet1[4][column_idx].style_index # copy style from top cell
          sheet1.add_cell(row_idx, column_idx, data)
          sheet1[row_idx][column_idx].style_index = style_index
        end
        row_idx += 1
      end
    end
    workbook
  end

  def table_data(fund, institutional_kyc_commitments, retail_kyc_commitments)
    data = hash_tree

    institutional_total_committed_capital = (institutional_kyc_commitments.sum(:committed_amount_cents) / 100.0) / 1_000_000.0
    retail_total_committed_capital = (retail_kyc_commitments.sum(:committed_amount_cents) / 100.0) / 1_000_000.0

    target_lp_commitments = nil
    target_gp_commitments = nil
    fund_currency = fund.currency

    first_close_date = fund.first_close_date&.strftime("%d-%b-%y")
    final_close_date = fund.last_close_date&.strftime("%d-%b-%y")

    institutional_first_close_size = (institutional_kyc_commitments.where(fund_close: FIRST_CLOSE_NAME).sum(:committed_amount_cents) / 100.0) / 1_000_000.0
    retail_first_close_size = (retail_kyc_commitments.where(fund_close: FIRST_CLOSE_NAME).sum(:committed_amount_cents) / 100.0) / 1_000_000.0

    institutional_final_close_size = (institutional_kyc_commitments.where(fund_close: FINAL_CLOSE_NAME).sum(:committed_amount_cents) / 100.0) / 1_000_000.0
    retail_final_close_size = (retail_kyc_commitments.where(fund_close: FINAL_CLOSE_NAME).sum(:committed_amount_cents) / 100.0) / 1_000_000.0

    unit_types = fund.fund_unit_settings.pluck(:name, :gp_units).to_h
    gp_unit_types = unit_types.select { |_, v| v }.keys
    lp_unit_types = unit_types.reject { |_, v| v }.keys
    final_close_lp_commitments_institutional = (institutional_kyc_commitments.where(fund_close: FINAL_CLOSE_NAME, unit_type: lp_unit_types).sum(:committed_amount_cents) / 100.0) / 1_000_000.0
    final_close_gp_commitments_institutional = (institutional_kyc_commitments.where(fund_close: FINAL_CLOSE_NAME, unit_type: gp_unit_types).sum(:committed_amount_cents) / 100.0) / 1_000_000.0
    final_close_lp_commitments_retail = (retail_kyc_commitments.where(fund_close: FINAL_CLOSE_NAME, unit_type: lp_unit_types).sum(:committed_amount_cents) / 100.0) / 1_000_000.0
    final_close_gp_commitments_retail = (retail_kyc_commitments.where(fund_close: FINAL_CLOSE_NAME, unit_type: gp_unit_types).sum(:committed_amount_cents) / 100.0) / 1_000_000.0

    first_call_date = fund.capital_calls.where(call_date: ..@end_date).present? ? fund.capital_calls.where(call_date: ..@end_date).order(:call_date).first.call_date&.strftime("%d-%b-%y") : ""

    first_investment_date = fund.portfolio_investments.where(investment_date: ..@end_date).present? ? fund.portfolio_investments.order(:investment_date).where(investment_date: ..@end_date).first.investment_date&.strftime("%d-%b-%y") : ""

    fund_of_funds = "No"
    data["Scheme Name"]["Value"] = fund.name
    data["Institutional Total Committed Capital"]["Value"] = institutional_total_committed_capital
    data["Retail Total Committed Capital"]["Value"] = retail_total_committed_capital
    data["Target LP Commitments"]["Value"] = target_lp_commitments
    data["Target GP Commitments"]["Value"] = target_gp_commitments
    data["Fund Currency"]["Value"] = fund_currency
    data["Investor Type"]["Value"] = "Institutional"
    data["First Close Date"]["Value"] = first_close_date
    data["Final Close Date"]["Value"] = final_close_date
    data["Institutional First Close Size"]["Value"] = institutional_first_close_size
    data["Institutional Final Close Size"]["Value"] = institutional_final_close_size
    data["Retail First Close Size"]["Value"] = retail_first_close_size
    data["Retail Final Close Size"]["Value"] = retail_final_close_size
    data["Final Close LP Commitments Institutional"]["Value"] = final_close_lp_commitments_institutional
    data["Final Close GP Commitments Institutional"]["Value"] = final_close_gp_commitments_institutional
    data["Final Close LP Commitments Retail"]["Value"] = final_close_lp_commitments_retail
    data["Final Close GP Commitments Retail"]["Value"] = final_close_gp_commitments_retail
    data["First Call Date"]["Value"] = first_call_date
    data["First Investment Date"]["Value"] = first_investment_date
    data["Fund of Funds"]["Value"] = fund_of_funds

    data
  end

  def get_row_data(fund, institutional_kyc_commitments, retail_kyc_commitments)
    scheme_name = fund.name

    # use with exchange rate in case we need to convert currency
    institutional_total_committed_capital = (institutional_kyc_commitments.sum(:committed_amount_cents) / 100.0) / 1_000_000.0
    retail_total_committed_capital = (retail_kyc_commitments.sum(:committed_amount_cents) / 100.0) / 1_000_000.0

    target_lp_commitments = nil
    target_gp_commitments = nil
    fund_currency = fund.currency

    # will the first close date and final close date be diff for institutional and retail?
    first_close_date = fund.first_close_date&.strftime("%d-%b-%y")
    final_close_date = fund.last_close_date&.strftime("%d-%b-%y")

    institutional_first_close_size = (institutional_kyc_commitments.where(fund_close: FIRST_CLOSE_NAME).sum(:committed_amount_cents) / 100.0) / 1_000_000.0
    retail_first_close_size = (retail_kyc_commitments.where(fund_close: FIRST_CLOSE_NAME).sum(:committed_amount_cents) / 100.0) / 1_000_000.0

    institutional_final_close_size = (institutional_kyc_commitments.where(fund_close: FINAL_CLOSE_NAME).sum(:committed_amount_cents) / 100.0) / 1_000_000.0
    retail_final_close_size = (retail_kyc_commitments.where(fund_close: FINAL_CLOSE_NAME).sum(:committed_amount_cents) / 100.0) / 1_000_000.0

    unit_types = fund.fund_unit_settings.pluck(:name, :gp_units).to_h
    gp_unit_types = unit_types.select { |_, v| v }.keys
    lp_unit_types = unit_types.reject { |_, v| v }.keys
    final_close_lp_commitments_institutional = (institutional_kyc_commitments.where(fund_close: FINAL_CLOSE_NAME, unit_type: lp_unit_types).sum(:committed_amount_cents) / 100.0) / 1_000_000.0
    final_close_gp_commitments_institutional = (institutional_kyc_commitments.where(fund_close: FINAL_CLOSE_NAME, unit_type: gp_unit_types).sum(:committed_amount_cents) / 100.0) / 1_000_000.0
    final_close_lp_commitments_retail = (retail_kyc_commitments.where(fund_close: FINAL_CLOSE_NAME, unit_type: lp_unit_types).sum(:committed_amount_cents) / 100.0) / 1_000_000.0
    final_close_gp_commitments_retail = (retail_kyc_commitments.where(fund_close: FINAL_CLOSE_NAME, unit_type: gp_unit_types).sum(:committed_amount_cents) / 100.0) / 1_000_000.0

    first_call_date = fund.capital_calls.where(call_date: ..@end_date).present? ? fund.capital_calls.where(call_date: ..@end_date).order(:call_date).first.call_date&.strftime("%d-%b-%y") : ""

    first_investment_date = fund.portfolio_investments.where(investment_date: ..@end_date).present? ? fund.portfolio_investments.order(:investment_date).where(investment_date: ..@end_date).first.investment_date&.strftime("%d-%b-%y") : ""

    # 7 fields are ignored

    fund_of_funds = "No"
    ret_val = []
    if institutional_kyc_commitments.present?
      investor_type = "Institutional"
      ret_val << [scheme_name, nil, nil, nil, nil, institutional_total_committed_capital, target_lp_commitments, target_gp_commitments, fund_currency, investor_type, nil, first_close_date, institutional_first_close_size, final_close_date, institutional_final_close_size, final_close_lp_commitments_institutional, final_close_gp_commitments_institutional, nil, first_call_date, first_investment_date, nil, nil, nil, nil, nil, nil, nil, fund_of_funds]
    else
      ret_val << nil
    end
    if retail_kyc_commitments.present?
      investor_type = "Retail"
      ret_val << [scheme_name, nil, nil, nil, nil, retail_total_committed_capital, target_lp_commitments, target_gp_commitments, fund_currency, investor_type, nil, first_close_date, retail_first_close_size, final_close_date, retail_final_close_size, final_close_lp_commitments_retail, final_close_gp_commitments_retail, nil, first_call_date, first_investment_date, nil, nil, nil, nil, nil, nil, nil, fund_of_funds]
    else
      ret_val << nil
    end
    ret_val
  end
  # rubocop:enable Metrics/MethodLength
end
