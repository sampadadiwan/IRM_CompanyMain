class CapitalCallApprove < CapitalCallAction
  step :check_unapproved_docs
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :generate_capital_remittances

  def check_unapproved_docs(ctx, capital_call:, **)
    # We need to check for unapproved but generated docs for the remittances of this call
    # exists? issues a LIMIT 1 query; present? would load every matching document row
    generated_not_approved = capital_call.remittance_documents.generated.not_approved

    if generated_not_approved.exists?
      capital_call.errors.add(:base, "There are unapproved documents for the remittances of this call. Please approve them first.")
      ctx[:errors] = "There are unapproved documents for the remittances of this call. Please approve them first."
      false
    else
      true
    end
  end
end
