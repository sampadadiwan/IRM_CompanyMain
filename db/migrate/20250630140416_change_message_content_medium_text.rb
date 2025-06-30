class ChangeMessageContentMediumText < ActiveRecord::Migration[8.0]
  def change
    change_column :messages, :content, :text, limit: 16.megabytes - 1
  end
end
