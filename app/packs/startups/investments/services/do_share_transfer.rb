class DoShareTransfer < HoldingAction
  step Subprocess(TransferCreateToInvestment)
  step Subprocess(TransferUpdateFromInvestment)
  step :create_share_transfer
  left :handle_error

  def create_share_transfer(_ctx, share_transfer:, **)
    share_transfer.save
  end
end
