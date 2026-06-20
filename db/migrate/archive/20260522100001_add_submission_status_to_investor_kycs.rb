class AddSubmissionStatusToInvestorKycs < ActiveRecord::Migration[7.2]
  def change
    add_column :investor_kycs, :submission_status, :string, default: "not_sent", null: false
    add_column :investor_kycs, :link_sent_at, :datetime
    add_column :investor_kycs, :submitted_at, :datetime
    add_index :investor_kycs, :submission_status
  end
end
