class TransferUpdateFromHolding < BaseShareTransferAction
  step :validate
  step :process
  left :handle_error

  def process(_ctx, share_transfer:, **)
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
