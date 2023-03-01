class AddAdvisorToInvestorAccess < ActiveRecord::Migration[7.0]
  def change
    add_column :investor_accesses, :is_investor_advisor, :boolean, default: false
    InvestorAccess.includes(user: :roles).all.each do |ia|
      if ia.user.has_cached_role?(:investor_advisor)
        ia.is_investor_advisor = true
        ia.save
      end
    end
  end
end
