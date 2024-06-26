class AddKanbanStepsToEntitySettings < ActiveRecord::Migration[7.1]
  def change
    add_column :entity_settings, :kanban_steps, :json
    EntitySetting.update_all(
      kanban_steps: {
        "Deal": [
          "Info Deck Sent", 
          "Business Plan Sent", 
          "NBO Received", 
          "Financial DD", 
          "Legal DD", 
          "Commercial DD", 
          "SHA / SSA", 
          "SPA", 
          "Remittance", 
          "Final Offer"
        ]
      }
    )    
  end
end
