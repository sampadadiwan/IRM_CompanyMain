class SetActiveDeal
  include Interactor

  def call
    Rails.logger.debug "Interactor: SetActiveDeal called"
    if context.deal.present?
      context.deal.save
      active_deal(context.deal)
    else
      Rails.logger.error "No Deal specified"
      context.fail!(message: "No Deal specified")
    end
  end

  def active_deal(deal)
    deal.entity.active_deal_id = deal.id
    deal.entity.save
  end
end
