class BaseShareTransferAction < Trailblazer::Operation
  def validate(ctx, share_transfer:, **)
    if share_transfer.pre_validation
      true
    else
      ctx[:errors] = "Invalid share transfer. pre_validation failed"
      false
    end
  end

  def handle_error(ctx, holding:, **)
    Rails.logger.error "Error approving holding #{holding.errors.full_messages.join(', ')}"
    ctx[:errors] = holding.errors.full_messages.join(", ")
  end
end
