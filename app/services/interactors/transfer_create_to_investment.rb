class TransferCreateToInvestment
  include Interactor

  def call
    Rails.logger.debug "Interactor: TransferCreateToInvestment called"

    if context.share_transfer.present?
      create_to_investment(context.share_transfer)
    else
      Rails.logger.debug "No share_transfer specified"
      context.fail!(message: "No share_transfer specified")
    end
  end

  def create_to_investment(share_transfer)
    from_investment = share_transfer.from_investment
    to_investment = share_transfer.build_to_investment

    to_investment.investment_type = from_investment.investment_type
    to_investment.category = from_investment.category
    to_investment.entity_id = from_investment.entity_id
    to_investment.currency = from_investment.currency
    to_investment.funding_round = from_investment.funding_round

    to_investment.investment_date = share_transfer.transfer_date

    # If this is a conversion from Preferred to Equity
    if share_transfer.transfer_type == "Conversion" && from_investment.investment_instrument == "Preferred"
      setup_conversion(share_transfer)
    else
      setup_transfer(share_transfer)
    end

    Rails.logger.debug to_investment.to_json

    SaveInvestment.call(investment: to_investment)
  end

  def setup_conversion(share_transfer)
    from_investment = share_transfer.from_investment
    to_investment = share_transfer.to_investment

    to_investment.investor_id = share_transfer.from_investor_id
    to_investment.quantity = share_transfer.quantity * from_investment.preferred_conversion
    to_investment.investment_instrument = "Equity"
    to_investment.price_cents = (from_investment.price_cents / from_investment.preferred_conversion).round(0)
    to_investment.preferred_conversion = 1

    share_transfer.to_quantity = share_transfer.quantity * from_investment.preferred_conversion
    share_transfer.price = to_investment.price_cents / 100
    share_transfer.to_investor_id = share_transfer.from_investor_id
  end

  def setup_transfer(share_transfer)
    from_investment = share_transfer.from_investment
    to_investment = share_transfer.to_investment

    to_investment.investor_id = share_transfer.to_investor_id
    to_investment.quantity = share_transfer.quantity
    to_investment.investment_instrument = from_investment.investment_instrument
    to_investment.price_cents = from_investment.price_cents
    to_investment.preferred_conversion = from_investment.preferred_conversion

    share_transfer.transfer_type ||= "Transfer"
    share_transfer.to_quantity = share_transfer.quantity
  end
end
