class RemoveFkFromDocument < ActiveRecord::Migration[7.1]
  def change
    remove_foreign_key :documents, column: :from_template_id
    remove_index :documents, column: :from_template_id
  end
end
