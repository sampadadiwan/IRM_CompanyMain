class TransferUpdateFromInvestment
  include Interactor

  def call
    Rails.logger.debug "Interactor: TransferUpdateFromInvestment called"

    share_transfer = context.share_transfer
    if share_transfer.present? && share_transfer.pre_validation
      update_from_investment(context.share_transfer)
    else
      Rails.logger.debug "No valid share_transfer specified"
      context.fail!(message: "No valid share_transfer specified")
    end
  end

  def update_from_investment(share_transfer)
    share_transfer.from_investment.quantity -= share_transfer.quantity

    msg = " #{share_transfer.transfer_type} of #{share_transfer.to_quantity} to #{share_transfer.to_investor.investor_name}"
    if share_transfer.from_investment.notes.present?
      share_transfer.from_investment.notes += msg
    else
      share_transfer.from_investment.notes = msg
    end

    SaveInvestment.call(investment: share_transfer.from_investment)
  end
end
