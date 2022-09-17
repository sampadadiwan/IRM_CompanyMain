class UpdateInvestorCategory
  include Interactor

  def call
    Rails.logger.debug "Interactor: UpdateInvestorCategory called"

    if context.investment.present?
      # Update the investor category to the investment category
      investor = context.investment.investor
      investor.category = context.investment.category
      context.fail!(message: investor.errors.full_messages) unless investor.save
    else
      Rails.logger.debug "No Investment specified"
      context.fail!(message: "No Investment specified")
    end
  end
end
