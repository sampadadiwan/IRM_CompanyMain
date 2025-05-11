class EoiUnapprove < EoiAction
  step :unapprove
  step :save
  step :repoint_investor_kyc_to_rm
  left :handle_errors, Output(:failure) => End(:failure)

  def unapprove(_ctx, expression_of_interest:, **)
    expression_of_interest.approved = false   
    true 
  end

  
  def repoint_investor_kyc_to_rm(ctx, expression_of_interest:, **)
    # We only want to repoint the investor_kyc if the user is a relationship manager, as they can create ROIs for their clients. Here the eoi is being un approved, so in approve the kyc has been pointed to the investor
    # and now we need to point it back to the relationship manager. the investor_id in the expression_of_interest is always the RM if created by an RM
    if expression_of_interest.user.has_cached_role?(:rm) && expression_of_interest.investor_kyc.present?
      # We need to repoint the investor_kyc to the new investor
      expression_of_interest.investor_kyc.update(investor_id: expression_of_interest.investor_id)
      # Since the kyc investor is chaning we need to update the document folder path
      UpdateDocumentFolderPathJob.perform_now("InvestorKyc", expression_of_interest.investor_kyc.id)
    end
    true
  end
end
