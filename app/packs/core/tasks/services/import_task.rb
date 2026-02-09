# frozen_string_literal: true

# Service for importing Tasks and Recurring Tasks.
class ImportTask < ImportUtil
  # Task does not have a custom_field model, so we skip the step that would try to create them.
  step nil, delete: :create_custom_fields

  STANDARD_HEADERS = ["Description", "Status", "Due Date", "Category", "Assignee Email", "Owner Type", "Owner Name", "Update Only", "Recurring", "Rrule", "Start Date", "End Date"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(row_data, import_upload, _custom_field_headers, _ctx)
    Rails.logger.error "### ImportTask save_row: #{row_data.inspect}"

    description = row_data["Description"]
    status = row_data["Status"]
    due_date = row_data["Due Date"].present? ? Date.local_parse(row_data["Due Date"]) : nil
    category = row_data["Category"]
    assignee_email = row_data["Assignee Email"]
    owner_type = row_data["Owner Type"]
    owner_name = row_data["Owner Name"]
    update_only = row_data["Update Only"]&.downcase == "yes"

    # Recurring task fields
    recurring = row_data["Recurring"]&.downcase == "yes"
    rrule = row_data["Rrule"]
    start_date = row_data["Start Date"].present? ? Date.local_parse(row_data["Start Date"]) : nil
    end_date = row_data["End Date"].present? ? Date.local_parse(row_data["End Date"]) : nil

    entity = import_upload.entity
    assignee = entity.employees.find_by(email: assignee_email) if assignee_email.present?

    owner = find_owner(entity, owner_type, owner_name)

    # In some contexts, import_upload.owner might be the entity or a fund/investor.
    # If no owner is specified in the row, we use the import_upload.owner as a fallback if it's valid.
    owner ||= import_upload.owner if import_upload.owner.present? && !import_upload.owner.is_a?(::Entity)

    # Final fallback: owner MUST be the entity if still nil, as Task requires an owner sometimes
    # but more importantly, entity_id is required.
    owner ||= entity

    if recurring
      save_recurring_task(entity, import_upload, description, category, assignee, owner, rrule, start_date, end_date, update_only)
    else
      save_normal_task(entity, import_upload, description, status, due_date, category, assignee, owner, update_only)
    end

    true
  end

  private

  def save_normal_task(entity, import_upload, description, status, due_date, category, assignee, owner, update_only)
    if update_only
      task = entity.tasks.find_by(due_date: due_date, owner_type: owner&.class&.name, owner_id: owner&.id)
      raise "Task not found for update" unless task

      task.update!(
        details: description,
        completed: status&.downcase == "completed",
        due_date: due_date,
        category: category,
        assigned_to_id: assignee&.id || task.assigned_to_id,
        import_upload_id: import_upload.id,
        user_id: import_upload.user_id,
        send_notification_flag: false # Skip notifications on import, especially for recurring tasks which will create multiple records
      )
    else
      Task.create!(
        entity_id: entity.id,
        details: description,
        completed: status&.downcase == "completed",
        due_date: due_date,
        category: category,
        user_id: import_upload.user_id,
        assigned_to_id: assignee&.id,
        owner: owner,
        import_upload_id: import_upload.id,
        send_notification_flag: false # Skip notifications on import, especially for recurring tasks which will create multiple records
      )
    end
  end

  def save_recurring_task(entity, _import_upload, description, category, assignee, owner, rrule, start_date, end_date, update_only)
    raise "Rrule and Start Date are required for recurring tasks" if rrule.blank? || start_date.blank?

    task_template_payload = {
      details: description,
      category: category,
      assigned_to_id: assignee&.id,
      owner_type: owner&.class&.name,
      owner_id: owner&.id
    }.compact

    if update_only
      rule = entity.task_recurrence_rules.find_by(rrule: rrule, start_date: start_date)
      raise "TaskRecurrenceRule not found for update" unless rule

      rule.update!(
        task_template_payload: task_template_payload,
        end_date: end_date
      )
    else
      TaskRecurrenceRule.create!(
        entity_id: entity.id,
        rrule: rrule,
        start_date: start_date,
        end_date: end_date,
        task_template_payload: task_template_payload
      )
    end
  end

  def find_owner(entity, owner_type, owner_name)
    return nil if owner_type.blank? || owner_name.blank?

    case owner_type
    when "Fund"
      entity.funds.find_by(name: owner_name)
    when "Investor", "PortfolioCompany"
      entity.investors.find_by(investor_name: owner_name)
    when "Entity"
      entity.name == owner_name ? entity : nil
    end
  end
end
