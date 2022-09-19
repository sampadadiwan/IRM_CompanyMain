class TransferCreateToHolding
  include Interactor

  def call
    Rails.logger.debug "Interactor: TransferCreateToHolding called"

    share_transfer = context.share_transfer

    Rails.logger.debug { "share_transfer.quantity_valid? = #{share_transfer.quantity_valid?}" }
    Rails.logger.debug { "share_transfer.investor_valid? = #{share_transfer.investor_valid?}" }
    Rails.logger.debug { "share_transfer.pre_validation = #{share_transfer.pre_validation}" }

    if share_transfer.present? && share_transfer.pre_validation
      create_to_investment(context.share_transfer)
    else
      Rails.logger.debug "No valid share_transfer specified"
      context.fail!(message: "No valid share_transfer specified")
    end
  end

  def create_to_investment(share_transfer)
    from_holding = share_transfer.from_holding
    share_transfer.from_user_id = share_transfer.from_holding.user_id

    # If this is a conversion from Preferred to Equity
    if share_transfer.transfer_type == "Conversion" && from_holding.investment_instrument == "Preferred"
      setup_conversion(share_transfer)
    else
      setup_transfer(share_transfer)
    end
  end

  def setup_conversion(share_transfer)
    from_holding = share_transfer.from_holding
    share_transfer.to_holding = share_transfer.from_holding.dup
    to_holding = share_transfer.to_holding

    to_holding.orig_grant_quantity = share_transfer.quantity * from_holding.preferred_conversion
    to_holding.investment_instrument = "Equity"
    to_holding.price_cents = (from_holding.price_cents / from_holding.preferred_conversion).round(0)
    to_holding.preferred_conversion = 1
    to_holding.investment_id = nil

    share_transfer.to_quantity = share_transfer.quantity * from_holding.preferred_conversion
    share_transfer.price = to_holding.price_cents / 100
    share_transfer.to_user_id = to_holding.user_id

    # puts to_holding.to_json

    to_holding = CreateHolding.call(holding: to_holding).holding
    ApproveHolding.call(holding: to_holding)
  end

  def setup_transfer(share_transfer)
    from_holding = share_transfer.from_holding
    to_investment = share_transfer.build_to_investment

    to_investment.entity_id = from_holding.entity_id
    to_investment.currency = from_holding.entity.currency
    to_investment.funding_round = from_holding.funding_round
    to_investment.investment_type = from_holding.funding_round.name
    to_investment.investment_instrument = from_holding.investment_instrument
    to_investment.price_cents = from_holding.price_cents
    to_investment.preferred_conversion = from_holding.preferred_conversion
    to_investment.category = share_transfer.to_investor.category

    to_investment.investor_id = share_transfer.to_investor_id
    to_investment.quantity = share_transfer.quantity
    to_investment.investment_date = share_transfer.transfer_date

    share_transfer.transfer_type ||= "Transfer"
    share_transfer.to_quantity = share_transfer.quantity

    msg = " #{share_transfer.transfer_type} of #{share_transfer.to_quantity} from #{share_transfer.from_holding.user.full_name}"
    if to_investment.notes.present?
      to_investment.notes += msg
    else
      to_investment.notes = msg
    end

    SaveInvestment.call(investment: to_investment)
  end
end
