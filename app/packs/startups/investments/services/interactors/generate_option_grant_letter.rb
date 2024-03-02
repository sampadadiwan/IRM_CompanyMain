class GenerateOptionGrantLetter
  include Interactor

  def call
    Rails.logger.debug "Interactor: HoldingApproved called"

    if context.holding.present?
      holding = context.holding
      if holding.investment_instrument == "Options" && holding.user.present?
        EsopLetterJob.perform_later(holding.id)
      else
        Rails.logger.debug { "GenerateOptionGrantLetter: Skipping as holding #{holding.id} not an option" }
      end
    else
      Rails.logger.debug "No Holding specified"
      context.fail!(message: "No Holding specified")
    end
  end
end
