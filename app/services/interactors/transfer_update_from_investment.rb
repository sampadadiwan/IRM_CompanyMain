class TransferUpdateFromInvestment
  include Interactor

  def call
    Rails.logger.debug "Interactor: TransferUpdateFromInvestment called"

    if context.share_transfer.present?
      update_from_investment(context.share_transfer)
    else
      Rails.logger.debug "No share_transfer specified"
      context.fail!(message: "No share_transfer specified")
    end
  end

  def update_from_investment(share_transfer)
    share_transfer.from_investment.quantity -= share_transfer.quantity
    SaveInvestment.call(investment: share_transfer.from_investment)
  end
end
