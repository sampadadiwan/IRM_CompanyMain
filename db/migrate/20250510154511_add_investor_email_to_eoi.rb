class AddInvestorEmailToEoi < ActiveRecord::Migration[8.0]
  def change
    add_column :expression_of_interests, :investor_email, :string
  end
end
