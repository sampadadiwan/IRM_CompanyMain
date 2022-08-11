class AddSnapshotToEntity < ActiveRecord::Migration[7.0]
  def change
    add_column :entities, :snapshot_frequency_months, :integer, default: 0
    add_column :entities, :last_snapshot_on, :date, default: Time.zone.today
  end
end
