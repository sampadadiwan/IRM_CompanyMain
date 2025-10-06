class AddDocsToAppendToDocument < ActiveRecord::Migration[8.0]
  def change
    add_column :documents, :template_docs_to_append, :string
  end
end
