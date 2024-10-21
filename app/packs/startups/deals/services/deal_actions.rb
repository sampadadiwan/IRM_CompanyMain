class DealActions < Trailblazer::Operation
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

  def create_deal_documents_folder(_ctx, deal:, **)
    deal.deal_documents_folder
    deal.save
  end
end
