class EoiApprove < EoiAction
  step :approve
  step :save
  step :create_investor
  step :repoint_investor_kyc_to_investor
  left :handle_errors, Output(:failure) => End(:failure)

  def approve(_ctx, expression_of_interest:, **)
    expression_of_interest.approved = true    
  end

  def create_investor(ctx, expression_of_interest:, **)
    # We only want to create an investor if the user is a relationship manager, as they can create ROIs for their clients
    if expression_of_interest.user.has_cached_role?(:rm)
      # See if we already have this investor
      investor = Investor.where(investor_name: expression_of_interest.investor_name, primary_email: expression_of_interest.investor_email, entity_id: expression_of_interest.entity_id).first

      # We need to create a new investor for the expression of interest    
      investor ||= Investor.create(investor_name: expression_of_interest.investor_name, primary_email: expression_of_interest.investor_email, entity_id: expression_of_interest.entity_id, category: "LP", description: "EOI Investor from IO: #{expression_of_interest.investment_opportunity_id},  EOI: #{expression_of_interest.id}")
      # Store it
      ctx[:investor] = investor
    end
    true
  end

  def repoint_investor_kyc_to_investor(ctx, expression_of_interest:, **)
    # We only want to repoint the investor_kyc if the user is a relationship manager, as they can create ROIs for their clients
    if expression_of_interest.user.has_cached_role?(:rm) && expression_of_interest.investor_kyc.present? 
      # We need to repoint the investor_kyc to the new investor
      expression_of_interest.investor_kyc.update(investor_id: ctx[:investor].id)
      # Since the kyc investor is chaning we need to update the document folder path
      UpdateDocumentFolderPathJob.perform_now("InvestorKyc", expression_of_interest.investor_kyc.id)
    end
    true
  end
end
