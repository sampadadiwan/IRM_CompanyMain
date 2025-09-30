class CreateAgentCharts < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_charts do |t|
      t.string :title
      t.text :prompt
      t.json :raw_data
      t.json :spec
      t.string :llm_model, limit: 20
      t.string :status, limit: 10
      t.text :error
      t.references :entity, null: false, foreign_key: true
      t.references :owner, polymorphic: true, null: true
      t.timestamps
    end
  end
end
