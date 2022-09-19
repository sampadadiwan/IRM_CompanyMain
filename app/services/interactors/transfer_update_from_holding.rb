class TransferUpdateFromHolding
  include Interactor

  def call
    Rails.logger.debug "Interactor: TransferUpdateFromHolding called"

    share_transfer = context.share_transfer
    if share_transfer.present? && share_transfer.pre_validation
      update_from_holding(context.share_transfer)
    else
      Rails.logger.debug "No valid share_transfer specified"
      context.fail!(message: "No valid share_transfer specified")
    end
  end

  def update_from_holding(share_transfer)
    share_transfer.from_holding.sold_quantity = share_transfer.quantity

    msg = " #{share_transfer.transfer_type} of #{share_transfer.to_quantity} to "
    msg += share_transfer.to_investment ? share_transfer.to_investor.investor_name : share_transfer.to_holding.user.full_name

    if share_transfer.from_holding.note.present?
      share_transfer.from_holding.note += msg
    else
      share_transfer.from_holding.note = msg
    end

    share_transfer.from_holding.save
  end
end
