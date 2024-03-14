class TransferUpdateFromInvestment < BaseShareTransferAction
  step :validate
  step :process

  def process(_ctx, share_transfer:, **)
    share_transfer.from_investment.quantity -= share_transfer.quantity

    msg = " #{share_transfer.transfer_type} of #{share_transfer.to_quantity} to #{share_transfer.to_investor.investor_name}"
    if share_transfer.from_investment.notes.present?
      share_transfer.from_investment.notes += msg
    else
      share_transfer.from_investment.notes = msg
    end

    SaveInvestment.call(investment: share_transfer.from_investment)
  end
end
