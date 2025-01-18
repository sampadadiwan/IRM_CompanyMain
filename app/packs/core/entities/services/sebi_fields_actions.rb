class SebiFieldsActions < Trailblazer::Operation
  def save(_ctx, entity:, **)
    entity.save
  end

  def handle_errors(ctx, entity:, **)
    entity.errors.add(:base, ctx[:errors]) if ctx[:errors].present?
    return false if entity.errors.present?

    unless entity.valid?
      ctx[:errors] = entity.errors.full_messages.join(", ")
      Rails.logger.error("Entity errors: #{entity.errors.full_messages}")
    end
    entity.valid?
  end
end
