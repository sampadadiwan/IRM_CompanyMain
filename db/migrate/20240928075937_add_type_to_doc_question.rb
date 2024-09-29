class AddTypeToDocQuestion < ActiveRecord::Migration[7.1]
  def change
    add_column :doc_questions, :qtype, :string, limit: 10
    add_column :doc_questions, :document_name, :string
    add_column :doc_questions, :for_class, :string, limit: 25
    add_reference :doc_questions, :owner, polymorphic: true, null: false
  end
end
