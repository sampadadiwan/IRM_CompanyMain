class OptionAction < Trailblazer::Operation
  def handle_error(ctx, option_pool:, **)
    Rails.logger.error option_pool.errors.full_messages.join(', ').to_s
    ctx[:errors] = option_pool.errors.full_messages.join(", ")
  end
end
