class AddLastSatusUpdatedAtToDocument < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:documents, :last_status_updated_at)
      add_column :documents, :last_status_updated_at, :datetime
    end
  end
end
