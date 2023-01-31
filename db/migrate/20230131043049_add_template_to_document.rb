class AddTemplateToDocument < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :template, :boolean, default: false

    Document.where("owner_tag like '%Template%'").update_all(template: true)
  end
end
