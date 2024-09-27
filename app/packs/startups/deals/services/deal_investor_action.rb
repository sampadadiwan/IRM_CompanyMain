class DealInvestorAction < Trailblazer::Operation
  def save(_ctx, deal_investor:, **)
    deal_investor.save
  end

  def handle_errors(ctx, deal_investor:, **)
    unless deal_investor.valid?
      ctx[:errors] = deal_investor.errors.full_messages.join(", ")
      Rails.logger.error("Investor KYC errors: #{deal_investor.errors.full_messages}")
    end
    deal_investor.valid?
  end

  def grant_access_to_deal(_ctx, deal_investor:, **)
    AccessRight.find_or_create_by(owner: deal_investor.deal, entity_id: deal_investor.entity_id, access_to_investor_id: deal_investor.investor_id)
  end
end
