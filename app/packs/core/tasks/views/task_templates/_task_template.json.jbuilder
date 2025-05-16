json.extract! task_template, :id, :details, :due_in_days, :action_link, :help_link, :position, :entity_id, :created_at, :updated_at
json.url task_template_url(task_template, format: :json)
