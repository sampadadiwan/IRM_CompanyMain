class CapitalCallApprove < CapitalCallAction
  step :check_unapproved_docs
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :generate_capital_remittances
  step :send_notification


  def check_unapproved_docs(ctx, capital_call:, **)
    # We need to check for unapproved but generated docs for the remittances of this call
    capital_remittance_ids = capital_call.capital_remittances.pluck(:id)
    generated_not_approved = capital_call.entity.documents.generated.not_approved
    generated_not_approved = generated_not_approved.where(owner_type: "CapitalRemittance", owner_id: capital_remittance_ids) 

    if generated_not_approved.present?
      capital_call.errors.add(:base, "There are unapproved documents for the remittances of this call. Please approve them first.")
      ctx[:errors] = "There are unapproved documents for the remittances of this call. Please approve them first."
      return false
    else
      return true
    end
  end
end
