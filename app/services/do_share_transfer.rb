class DoShareTransfer
  include Interactor::Organizer
  organize TransferCreateToInvestment, TransferUpdateFromInvestment, CreateShareTransfer

  before do |_organizer|
    context.audit_comment = "Transfer from #{context.share_transfer.from_investor.investor_name} to #{context.share_transfer.to_investor.investor_name}"
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
