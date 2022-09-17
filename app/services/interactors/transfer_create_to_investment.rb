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
    to_investment.investment_instrument = from_investment.investment_instrument
    to_investment.category = from_investment.category
    to_investment.entity_id = from_investment.entity_id

    to_investment.investor_id = share_transfer.to_investor_id
    to_investment.quantity = share_transfer.quantity
    to_investment.price = share_transfer.price
    to_investment.investment_date = share_transfer.transfer_date
    to_investment.currency = from_investment.currency
    to_investment.funding_round = from_investment.funding_round

    SaveInvestment.call(investment: to_investment)

    Rails.logger.debug to_investment.errors.full_messages
  end
end
