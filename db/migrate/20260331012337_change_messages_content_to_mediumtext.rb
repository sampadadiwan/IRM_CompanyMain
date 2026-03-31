class ChangeMessagesContentToMediumtext < ActiveRecord::Migration[8.1]
  def up
    change_column :messages, :content, :mediumtext
  end

  def down
    change_column :messages, :content, :text
  end
end
