class InformationOnInvestmentsJob
  include CurrencyHelper

  TABLE_OFFSET = 3

  REPORT_NAME = "InformationOnInvestments".freeze

  def hash_tree
    Hash.new do |hash, key|
      hash[key] = hash_tree
    end
  end

  # rubocop : disable Metrics/MethodLength
  # rubocop : disable Metrics/BlockLength
  def generate_report(fund_id, start_date, end_date)
    Rails.logger.debug { "Table 4: Generating Report for #{fund_id}, #{start_date}, #{end_date} " }

    @fund = Fund.find(fund_id)
    @fund_report = FundReport.find_or_initialize_by(name: REPORT_NAME, name_of_scheme: @fund.name, fund: @fund, entity_id: @fund.entity_id, start_date:, end_date:)

    data = hash_tree
    @fund.aggregate_portfolio_investments.each_with_index do |api, index|
      inv_instrument = api.investment_instrument
      Rails.logger.info "Skipping #{api.id} as it has no investment instrument"
      next if inv_instrument.blank?

      if api.portfolio_investments.where(investment_date: ..end_date).blank?
        Rails.logger.info "Skipping Aggregate Portfolio Investment #{api.id} as it has no portfolio investments with investment date before the end date"
        next
      end

      data[index]["Name of Scheme"]["Value"] = @fund.name
      data[index]["Name of Investee Company"]["Value"] = api.portfolio_company_name
      data[index]["PAN of Investee Company if available"]["Value"] = api.portfolio_company.pan

      data[index]["Type of Investee Company"]["Value"] = inv_instrument.custom_fields.type_of_investee_company
      data[index]["Type of Security"]["Value"] = inv_instrument.custom_fields.type_of_security
      data[index]["Other Security Type"]["Value"] = inv_instrument.custom_fields.details_of_security
      data[index]["Whether its an offshore investment?"]["Value"] = inv_instrument.custom_fields.offshore_investment
      data[index]["ISIN"]["Value"] = inv_instrument.custom_fields.isin
      data[index]["SEBI Registration Number of investee Company"]["Value"] = inv_instrument.custom_fields.sebi_registration_number
      data[index]["Whether Investee company is an Associate"]["Value"] = inv_instrument.custom_fields.is_associate
      data[index]["Whether it is managed or sponsored by AIF's manager or sponsor or their associates"]["Value"] = inv_instrument.custom_fields.is_managed_or_sponsored_by_aif
      data[index]["Sector"]["Value"] = inv_instrument.custom_fields.sector

      api_as_of_date = api.as_of(end_date)
      # pis = api.portfolio_investments.where("investment_date <= ?", end_date)
      # bought_amount = pis.buys.sum(&:amount)
      # cost_of_sold = pis.sells.sum(&:cost_of_sold)
      # cost = bought_amount + cost_of_sold
      data[index]["Amount Invested (for all investments including offshore) (Rs. Cr)"]["Value"] = money_to_currency(api_as_of_date.cost_of_remaining)

      data[index]["Amount invested (for offshore investment only) in $Mn"]["Value"] = money_to_currency(Money.new(0))

      data[index]["Latest Value of Investment in Rs. Cr"]["Value"] = money_to_currency(api_as_of_date.fmv)
      data[index]["Date of valuation of column O"]["Value"] = inv_instrument.portfolio_company.valuations.where(valuation_date: ..end_date).where(investment_instrument_id: inv_instrument.id).last&.valuation_date&.strftime("%d-%m-%Y") || ""
    end
    ######### Save the report

    @fund_report.data = data
    @fund_report.save!
  end

  def generate_excel_report(fund_id, _start_date, end_date, excel, single: false)
    primary_fund = Fund.find(fund_id)
    sheet = excel.worksheet(SebiReportJob::REPORT_TO_SHEET[REPORT_NAME])

    funds = primary_fund.entity.funds
    funds = funds.where(id: fund_id) if single

    funds.each do |fund|
      name_of_scheme = fund.name
      Rails.logger.debug { "InformationOnInvestments for #{name_of_scheme}" }
      fund.aggregate_portfolio_investments.each_with_index do |api, index|
        investee_company_name = api.portfolio_company_name
        pan = api.portfolio_company.pan
        row_index = index + TABLE_OFFSET
        sr_no = index + 1
        inv_instrument = api.investment_instrument
        next if inv_instrument.blank?

        if api.portfolio_investments.where(investment_date: ..end_date).blank?
          Rails.logger.info "Skipping Aggregate Portfolio Investment #{api.id} as it has no portfolio investments with investment date before the end date"
          next
        end
        type_of_investee_company = inv_instrument.custom_fields.type_of_investee_company
        type_of_security = inv_instrument.custom_fields.type_of_security
        details_of_security = inv_instrument.custom_fields.details_of_security
        offshore_investment = inv_instrument.custom_fields.offshore_investment
        isin = inv_instrument.custom_fields.isin
        sebi_registration_number = inv_instrument.custom_fields.sebi_registration_number
        is_associate = inv_instrument.custom_fields.is_associate
        is_managed_or_sponsored_by_aif = inv_instrument.custom_fields.is_managed_or_sponsored_by_aif
        sector = inv_instrument.custom_fields.sector

        api_as_of_date = api.as_of(end_date)
        amount_invested = api_as_of_date.cost_of_remaining.to_d

        amount_invested_in_offshore = Money.new(0).amount.to_d
        # Money.new(api_as_of_date.portfolio_investments.where("investment_date <= ?", end_date).where("quantity > 0").where(investment_domicile: "Overseas").sum(&:amount)).amount.to_d

        latest_value_of_investment = api_as_of_date.fmv.amount.to_d
        date_of_valuation = inv_instrument.portfolio_company.valuations.where(valuation_date: ..end_date).where(investment_instrument_id: inv_instrument.id).last&.valuation_date&.strftime("%d-%m-%Y") || ""
        row_data = [sr_no, name_of_scheme, investee_company_name, pan, type_of_investee_company, type_of_security, details_of_security, offshore_investment, isin, sebi_registration_number, is_associate, is_managed_or_sponsored_by_aif, sector, amount_invested, amount_invested_in_offshore, latest_value_of_investment, date_of_valuation]

        if index.zero?
          sheet.update_row(row_index, *row_data)
        else
          sheet.insert_row(row_index, row_data)
        end
      end
    end

    excel
  end
  # rubocop : enable Metrics/MethodLength
  # rubocop : enable Metrics/BlockLength
end
