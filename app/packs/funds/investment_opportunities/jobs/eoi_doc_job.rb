class EoiDocJob < DocGenJob
  def templates(_model = nil)
    @investment_opportunity.documents.templates
  end

  def models
    [@expression_of_interest]
  end

  def validate(_expression_of_interest)
    return false, "No Expression of Interest found" if @expression_of_interest.blank?
    return false, "InvestorKyc not verified" if @investor_kyc.blank? || !@investor_kyc.verified

    [true, ""]
  end

  def generator
    EoiDocGenerator
  end

  def cleanup_previous_docs(model, template)
    model.documents.not_templates.where(name: template.name).find_each(&:destroy)
  end

  # This is idempotent, we should be able to call it multiple times for the same ExpressionOfInterest
  def perform(expression_of_interest_id, _user_id = nil)
    Chewy.strategy(:sidekiq) do
      @expression_of_interest = ExpressionOfInterest.find(expression_of_interest_id)
      @investment_opportunity = @expression_of_interest.investment_opportunity
      @investor = @expression_of_interest.investor
      @investor_kyc = @expression_of_interest.investor_kyc
      @templates = @investment_opportunity.documents.templates

      @start_date = Time.zone.today
      @end_date = Time.zone.today

      generate(@start_date, @end_date, @user_id) if valid_inputs
    end

    nil
  end
end
