class AddWillReceiveEmailToInvestor < ActiveRecord::Migration[8.0]
  def change
    add_column :investors, :will_receive_email, :integer, default: 0, null: false
    InvestorAccess.counter_culture_fix_counts
  end
end
