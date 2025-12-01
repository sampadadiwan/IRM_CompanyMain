class CreateSupportAgents < ActiveRecord::Migration[8.0]
  def change
    create_table :support_agents do |t|
      t.string :name, limit: 30
      t.string :description
      t.references :entity, null: false, foreign_key: true
      t.references :form_type, null: true, foreign_key: true
      t.string :agent_type, limit: 20
      t.json :json_fields
      t.references :document_folder, null: true, foreign_key: {to_table: :folders}

      t.timestamps
    end
  end
end
