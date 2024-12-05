class CapitalRemittanceDocJob < DocGenJob
  def templates(model = nil)
    if @template_id.present?
      [Document.find(@template_id)]
    elsif model.present?
      model.capital_commitment.templates("Call Template")
    else
      @fund.documents.templates.where(owner_tag: "Call Template")
    end
  end

  def models
    if @capital_remittance_id.present?
      [CapitalRemittance.find(@capital_remittance_id)]
    else
      @capital_call.capital_remittances
    end
  end

  def validate(capital_remittance)
    return false, "No Capital Remittance found" if capital_remittance.blank?
    return false, "InvestorKyc not verified" if capital_remittance.investor_kyc.blank? || !capital_remittance.investor_kyc.verified

    [true, ""]
  end

  def generator
    CapitalRemittanceDocGenerator
  end

  def cleanup_previous_docs(model, template)
    # Delete any existing signed documents
    model.documents.not_templates.where(name: template.name).find_each(&:destroy)
  end

  def generate_doc_name(model, template, _start_date, _end_date)
    "#{template.name} - #{model}"
  end

  # This is idempotent, we should be able to call it multiple times for the same CapitalRemittance
  def perform(capital_call_id, capital_remittance_id, user_id, template_id: nil)
    @capital_call_id = capital_call_id
    @capital_call = CapitalCall.find(capital_call_id)
    @fund = @capital_call.fund
    @capital_remittance_id = capital_remittance_id

    @start_date = Time.zone.now
    @end_date = Time.zone.now
    @user_id = user_id
    @template_id = template_id

    Chewy.strategy(:sidekiq) do
      generate(@start_date, @end_date, @user_id) if valid_inputs
    end

    @error_msg
  end
end
