class AddStatusChangedAtToDealInvestors < ActiveRecord::Migration[7.1]
  def change
    add_column :deal_investors, :status_changed_at, :datetime

    # Backfill existing rows: best available proxy is updated_at
    reversible do |dir|
      dir.up { execute "UPDATE deal_investors SET status_changed_at = updated_at WHERE status_changed_at IS NULL" }
    end
  end
end
