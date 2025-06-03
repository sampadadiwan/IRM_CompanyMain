class AdjustmentDestroy < AdjustmentAction
  step :validate
  step :destroy
  left :handle_errors, Output(:failure) => End(:failure)
  step :update_commitment
  left :handle_commitment_errors
  step :update_owner
  step :touch_investor

  def destroy(_ctx, commitment_adjustment:, **)
    commitment_adjustment.destroy
  end
end
