class DoHoldingTransfer
  include Interactor::Organizer
  organize TransferCreateToHolding, TransferUpdateFromHolding, CreateShareTransfer

  before do |_organizer|
    context.audit_comment = "#{context.share_transfer.transfer_type} from #{context.share_transfer.from_holding.user.full_name}"
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
