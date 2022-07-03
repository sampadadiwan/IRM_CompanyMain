class SaveInvestment
  include Interactor::Organizer
  organize CreateAggregateInvestment, InvestmentSave, UpdateInvestorHoldings, UpdateInvestorCategory, CreateAuditTrail

  before do |_organizer|
    context.audit_comment ||= "Save Investment"
  end

  around do |organizer|
    ActiveRecord::Base.transaction do
      organizer.call
    end
  rescue StandardError => e
    Rails.logger.error e.message
    Rails.logger.error context.investment.to_json
  end

  # Ensure that the percentages are recomputed
  after do |_organizer|
    context.investment.entity.recompute_investment_percentages
  end
end
