class SetupStartup
  include Interactor::Organizer
  organize SetupFolders, SetupHoldingEntity

  around do |organizer|
    ActiveRecord::Base.transaction do
      organizer.call
    end
  rescue StandardError => e
    Rails.logger.error e.message
    Rails.logger.error context.entity.to_json
  end
end
