class DoHoldingTransfer < HoldingAction
  step Subprocess(TransferCreateToHolding)
  step Subprocess(TransferUpdateFromHolding)
  step :create_share_transfer
  left :handle_error

  def create_share_transfer(_ctx, share_transfer:, **)
    share_transfer.save
  end
end
