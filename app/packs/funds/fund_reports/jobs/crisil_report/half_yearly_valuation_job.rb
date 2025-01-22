class HalfYearlyValuationJob
  include CurrencyHelper

  REPORT_NAME = "HalfYearlyValuation".freeze
  TABLE_OFFSET = 3

  def hash_tree
    Hash.new do |hash, key|
      hash[key] = hash_tree
    end
  end

  def generate_report(fund_id, start_date, end_date)
    Rails.logger.debug { "Generating Half-yearly valuation Report for #{fund_id}, #{start_date}, #{end_date} " }

    @fund = Fund.includes(:account_entries).find(fund_id)
    @end_date = end_date
    @fund_report = FundReport.find_or_initialize_by(name: REPORT_NAME, name_of_scheme: @fund.name, fund: @fund, entity_id: @fund.entity_id, start_date:, end_date:)

    data = hash_tree

    data.merge!(table_data(@fund))

    ######### Save the report
    @fund_report.data = data
    @fund_report.save!
  end

  def generate_excel_report(fund_id, _start_date, end_date, workbook, single: false)
    fund = Fund.includes(:account_entries).find(fund_id)
    @end_date = end_date
    sheet1 = workbook[CrisilReportJob::REPORT_TO_SHEET[REPORT_NAME]]

    funds = single ? [fund] : fund.entity.funds
    funds.each do |scheme|
      scheme_name = scheme.name
      Rails.logger.debug { "Half-yearly valuation for #{scheme_name}" }
      rows = get_row_data(scheme)
      row_idx = TABLE_OFFSET
      Rails.logger.debug rows

      rows.each do |row_data|
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
    account_entries = fund.account_entries.where(reporting_date: ..@end_date, folio_id: [nil, ""], name: ["NAV Pre Carry", "NAV Post Carry"]).order(:reporting_date)
    account_entries.each do |entry|
      date_str = entry.reporting_date.strftime("%d-%m-%Y")
      data[date_str]["Scheme Name"]["Value"] = fund.name
      data[date_str]["Date"]["Value"] = entry.reporting_date.strftime("%d-%b-%y")
      val = (entry.amount_cents / 100.0) / 1_000_000.0
      if entry.name.casecmp?("NAV Pre Carry")
        data[date_str]["NAV Pre Carry"]["Value"] = val
      else
        data[date_str]["NAV Post Carry"]["Value"] = val
      end
    end
    data
  end

  def get_row_data(fund)
    scheme_name = fund.name
    rows = []
    data = table_data(fund)
    data.each_value do |values|
      next unless values["NAV Pre Carry"]["Value"].present? || values["NAV Post Carry"]["Value"].present?

      row = []
      row << values["Date"]["Value"]
      row << scheme_name
      row << ""
      row << values["NAV Pre Carry"]["Value"]
      row << values["NAV Post Carry"]["Value"]
      rows << row
    end
    rows
  end
end
