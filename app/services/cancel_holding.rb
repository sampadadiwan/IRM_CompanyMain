class CancelHolding
  include Interactor::Organizer
  organize HoldingCancelled, NotifyHoldingCancelled, CreateAuditTrail

  before do |_organizer|
    context.audit_comment = "Cancel Holding"
  end

  around do |organizer|
    ActiveRecord::Base.transaction do
      organizer.call
    end
  rescue StandardError => e
    Rails.logger.error e.message
    Rails.logger.error context.holding.to_json
  end

  after do
    if context.holding.option_pool
      # The trust must be updated only after the counter caches have updated the option pool
      context.holding.option_pool.reload
      UpdateTrustHoldings.call(holding: context.holding)
    end
  end
end
