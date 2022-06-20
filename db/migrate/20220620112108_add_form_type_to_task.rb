class AddFormTypeToTask < ActiveRecord::Migration[7.0]
  def change
    add_reference :tasks, :form_type, null: true, foreign_key: true
    add_reference :valuations, :form_type, null: true, foreign_key: true
  end
end
