class AddKnowledgeBaseToFolder < ActiveRecord::Migration[8.0]
  def change
    add_column :folders, :knowledge_base, :boolean, default: false
  end
end
