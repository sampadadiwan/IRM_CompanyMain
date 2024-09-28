class UpdateDeal < Trailblazer::Operation
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :grant_access

  def save(_ctx, deal:, **)
    deal.save
  end

  def handle_errors(ctx, deal:, **)
    unless deal.valid?
      ctx[:errors] = deal.errors.full_messages.join(", ")
      Rails.logger.error("Investor KYC errors: #{deal.errors.full_messages}")
    end
    deal.valid?
  end

  def grant_access(_ctx, deal:, **)
    deal.deal_investors.each do |deal_investor|
      AccessRight.find_or_create_by(owner: deal, entity_id: deal.entity_id, access_to_investor_id: deal_investor.investor_id)
    end
  end
end
