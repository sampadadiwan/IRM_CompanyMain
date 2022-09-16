class PreferredConvert
  include Interactor::Organizer
  organize CreateEquity, UpdatePreferred, CreateAuditTrail

  before do |_organizer|
    context.audit_comment = "Convert Preferred to Equity"
  end

  around do |organizer|
    ActiveRecord::Base.transaction do
      organizer.call
    end
  rescue StandardError => e
    Rails.logger.error e.message
    Rails.logger.error context.investment.to_json
    raise e
  end
end
