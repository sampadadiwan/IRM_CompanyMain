class CreateShareTransfer
  include Interactor

  def call
    Rails.logger.debug "Interactor: CreateShareTransfer called"

    if context.share_transfer.present?
      create_share_transfer(context.share_transfer)
    else
      Rails.logger.debug "No share_transfer specified"
      context.fail!(message: "No share_transfer specified")
    end
  end

  def create_share_transfer(share_transfer)
    share_transfer.save!
  end
end
