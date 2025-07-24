class CreateInvestorAccessForInvestorAdvisor < Trailblazer::Operation
  step :find_or_create_investor_access

  def find_or_create_investor_access(ctx, investor:, user:, entity_id:, granted_by_user_id:, **)
    investor_access = investor.investor_accesses.find_by(email: user.email, entity_id: entity_id)
    if investor_access.blank?
      investor_access = investor.investor_accesses.new(email: user.email, first_name: user.first_name, last_name: user.last_name, email_enabled: true, approved: true, send_confirmation: false, entity_id: entity_id, granted_by: granted_by_user_id)
      unless investor_access.save
        ctx[:errors] = investor_access.errors.full_messages.join(", ")
        return false
      end
    end
    ctx[:investor_access] = investor_access
    true
  end
end
