class AddBirthDateToInvestorKyc < ActiveRecord::Migration[7.0]
  def change
    add_column :investor_kycs, :birth_date, :datetime
  end
end
