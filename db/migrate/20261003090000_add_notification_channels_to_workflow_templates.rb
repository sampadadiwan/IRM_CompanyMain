class AddNotificationChannelsToWorkflowTemplates < ActiveRecord::Migration[8.1]
  def change
    change_table :workflow_templates, bulk: true do |t|
      # Email stays on for every existing template; WhatsApp is opt-in per template
      t.boolean :notify_by_email, default: true, null: false,
                                  comment: "Send workflow emails (step activation, reminders, review needed, journey complete) for this template"
      t.boolean :notify_by_whatsapp, default: false, null: false,
                                     comment: "Also send workflow messages on WhatsApp — only ever to employees of the entity"
    end
  end
end
