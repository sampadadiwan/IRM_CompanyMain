class CreateInvestorAdvisors < ActiveRecord::Migration[7.0]
  def change
    create_table :investor_advisors do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :email

      t.timestamps
    end
  end
end
