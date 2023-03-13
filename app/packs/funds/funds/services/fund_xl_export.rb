class FundXlExport
  def generate(fund)
    p = Axlsx::Package.new
    workbook = p.workbook

    add_commitments(fund, workbook)
    add_fund_ratios(fund, workbook)
    add_fund_units(fund, workbook)
    add_account_entries(fund, workbook)

    export_file_name = "tmp/#{fund.name}.xlsx"
    p.serialize export_file_name
    export_file_name
  end

  def add_fund_ratios(fund, workbook)
    fund_ratios_sheet = workbook.add_worksheet(name: 'Fund Ratios') do |sheet|
      sheet.add_row(["Fund", "Folio No", "Investor", "Name", "Value", "Display Value", "End Date", "Notes"])

      # Generate some data
      fund.fund_ratios.includes(:capital_commitment, :fund).each_with_index do |fr, _idx|
        sheet.add_row [fr.fund.name, fr.capital_commitment&.folio_id, fr.capital_commitment&.investor_name, fr.name, fr.value, fr.display_value, fr.end_date, fr.notes]
      end
    end

    workbook.add_worksheet(name: 'Fund Ratio Pivot') do |sheet|
      sheet.add_pivot_table 'A4:F50', 'A1:H1000', sort_on_headers: ['Folio No'] do |pivot_table|
        pivot_table.data_sheet = fund_ratios_sheet
        pivot_table.rows = ['Folio No']
        pivot_table.columns = ['Name']
        pivot_table.data = [ref: 'Value', num_fmt: 4]
        pivot_table.pages = ['End Date']
      end
    end
  end

  def add_fund_units(fund, workbook)
    fund_units_sheet = workbook.add_worksheet(name: 'Fund Units') do |sheet|
      sheet.add_row(["Fund", "Investor", "Folio No", "Unit Type", "Issue Date", "Quantity", "Price", "Premium", "Total Premium", "Reason"])

      # Generate some data
      fund.fund_units.includes(:capital_commitment, :fund).each_with_index do |fu, _idx|
        sheet.add_row [fu.fund.name, fu.capital_commitment.investor_name, fu.capital_commitment.folio_id, fu.unit_type, fu.issue_date, fu.quantity, fu.price, fu.premium, fu.total_premium, fu.reason]
      end
    end

    workbook.add_worksheet(name: 'Fund Units Pivot') do |sheet|
      sheet.add_pivot_table 'A4:F50', 'A1:J1000', sort_on_headers: ['Folio No'] do |pivot_table|
        pivot_table.data_sheet = fund_units_sheet
        pivot_table.rows = ['Folio No']
        pivot_table.columns = ['Unit Type']
        pivot_table.data = [ref: 'Quantity', num_fmt: 4]
        pivot_table.pages = ['Reason']
      end
    end
  end

  def add_account_entries(fund, workbook)
    account_entries_sheet = workbook.add_worksheet(name: 'Account Entries') do |sheet|
      sheet.add_row(["Fund", "Investor", "Folio", "Reporting Date", "Period", "Entry Type", "Name", "Folio Currency", "Folio Amount", "Fund Currency", "Amount", "Cumulative"])

      # Generate some data
      fund.account_entries.includes(:capital_commitment, :fund).each_with_index do |ae, _idx|
        cumulative = ae.cumulative ? "Yes" : "No"
        amount = ae.name.include?("Percentage") ? ae.amount_cents : ae.amount
        sheet.add_row [ae.fund.name, ae.capital_commitment&.investor_name, ae.capital_commitment&.folio_id, ae.reporting_date, ae.period, ae.entry_type, ae.name, ae.capital_commitment&.folio_currency, ae.folio_amount, ae.fund.currency, amount, cumulative]
      end
    end

    workbook.add_worksheet(name: 'Account Entry Pivot') do |sheet|
      sheet.add_pivot_table 'A4:F50', 'A1:L1000', sort_on_headers: ['Folio'] do |pivot_table|
        pivot_table.data_sheet = account_entries_sheet
        pivot_table.rows = ['Folio']
        pivot_table.columns = ['Name']
        pivot_table.data = [ref: 'Amount', num_fmt: 4]
        pivot_table.pages = ['Cumulative']
      end
    end
  end

  def add_commitments(fund, workbook)
    commitments_sheet = workbook.add_worksheet(name: 'Commitments') do |sheet|
      sheet.add_row ['Investor Name', 'Folio No', 'Unit Type', 'Fund Close', 'Committed', 'Called', 'Collected', 'Distribution']

      # Generate some data
      fund.capital_commitments.each_with_index do |cc, _idx|
        sheet.add_row [cc.investor_name, cc.folio_id, cc.unit_type, cc.fund_close, cc.committed_amount, cc.call_amount, cc.collected_amount, cc.distribution_amount]
      end
    end

    workbook.add_worksheet(name: 'Commitment Pivot') do |sheet|
      sheet.add_pivot_table 'A4:F17', 'A1:H1000', sort_on_headers: ['Committed'] do |pivot_table|
        pivot_table.data_sheet = commitments_sheet
        pivot_table.rows = ['Unit Type']
        pivot_table.data = %w[Committed Called Collected]
        pivot_table.pages = ['Investor Name']
      end
    end
  end
end
