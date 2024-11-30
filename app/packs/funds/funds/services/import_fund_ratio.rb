class ImportFundRatio < ImportUtil
  STANDARD_HEADERS = ["Fund", "Investor", "Folio No", "Instrument", "Ratio Name", "Value", "Display Value", "End Date"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def initialize(**)
    super
    @fund_ratios = []
  end

  def save_row(user_data, import_upload, _custom_field_headers, _ctx)
    Rails.logger.debug { "Processing Fund Ratio #{user_data}" }

    fund = Fund.find_by(name: user_data["Fund"])
    raise "Fund not found for #{user_data['Fund']}" if fund.nil?

    entity = import_upload.entity

    owner = if user_data["Instrument"].present? && user_data["Investor"].present?
              investor = entity.investors.find_by(investor_name: user_data["Investor"])
              raise "Investor not found for #{user_data['Investor']}" if investor.nil?

              instrument = investor.investment_instruments.find_by(name: user_data["Instrument"])
              raise "Instrument not found for #{user_data['Instrument']}" if instrument.nil?

              instrument.aggregate_portfolio_investment.find_by(fund_id: fund.id)
            elsif user_data["Investor"].present? && user_data["Instrument"].blank?
              entity.investors.find_by(investor_name: user_data["Investor"]).tap do |investor|
                raise "Investor not found for #{user_data['Investor']}" if investor.nil?
              end
            elsif user_data["Folio No"].present?
              fund.capital_commitments.find_by(folio_id: user_data["Folio No"]).tap do |capital_commitment|
                raise "Capital Commitment not found for #{user_data['Folio No']}" if capital_commitment.nil?
              end
            else
              fund
            end

    raise "Owner not found for #{user_data}" if owner.nil?

    fund_ratio = FundRatio.new(
      fund_id: fund.id,
      entity_id: entity.id,
      owner_type: owner.class.name,
      owner_id: owner.id,
      name: user_data["Ratio Name"],
      value: user_data["Value"].to_d,
      display_value: user_data["Display Value"],
      end_date: Date.parse(user_data["End Date"]),
      import_upload_id: import_upload.id
    )

    fund_ratio.capital_commitment_id = owner.id if owner.instance_of?(CapitalCommitment)

    fund_ratio.save!
  end
end
