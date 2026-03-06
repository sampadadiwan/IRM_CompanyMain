class CreateTaskRecurrenceRules < ActiveRecord::Migration[8.1]
  def change
    create_table :task_recurrence_rules do |t|
      t.references :entity, null: false, foreign_key: true
      t.json :task_template_payload
      t.string :rrule
      t.datetime :start_date
      t.datetime :end_date
      t.integer :max_occurrences
      t.datetime :generated_until

      t.timestamps
    end
  end
end
