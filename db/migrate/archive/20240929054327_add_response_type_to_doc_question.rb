class AddResponseTypeToDocQuestion < ActiveRecord::Migration[7.1]
  def change
    add_column :doc_questions, :response_hint, :string
  end
end
