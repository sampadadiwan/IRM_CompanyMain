class AddJsEventsToFormCustomFields < ActiveRecord::Migration[7.2]
  def change
    unless column_exists?(:form_custom_fields, :js_events)
      add_column :form_custom_fields, :js_events, :string
    end
  end
end
