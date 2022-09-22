class CreateDeal
  include Interactor::Organizer
  organize SetActiveDeal, CreateActivityTemplate

  around do |organizer|
    ActiveRecord::Base.transaction do
      organizer.call
    end
  rescue StandardError => e
    Rails.logger.error e.message
    Rails.logger.error context.deal.to_json
    raise e
  end
end
