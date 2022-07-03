class ApproveOptionPool
  include Interactor::Organizer
  organize ApprovePool, SetupTrustHoldings, CreateAuditTrail

  before do |_organizer|
    context.audit_comment = "Approve Option Pool"
  end

  around do |organizer|
    ActiveRecord::Base.transaction do
      organizer.call
    end
  rescue StandardError => e
    Rails.logger.error e.message
    Rails.logger.error context.option_pool.to_json
  end
end
