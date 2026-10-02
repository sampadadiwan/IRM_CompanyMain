module WorkflowTemplatesHelper
  # Returns ordered User records for the current entity, used to populate
  # actor select menus in template/step forms.
  def entity_users_for_select
    User.where(entity_id: current_user.entity_id).order(:first_name, :last_name)
  end

  # Confirmation text for the Enable/Disable button, on the template list and the template page.
  # Spells out both halves of the switch, because the half people get wrong is what happens to work
  # that is already under way: nothing. For a journey template it also says what new records lose —
  # the whole journey, since the step bar only exists where an instance was launched.
  def workflow_template_toggle_message(template)
    unless template.enabled
      return "\"#{template.name}\" will be used again: records created from now on can be assigned " \
             "and launched on it. Records created while it was disabled are not given one retrospectively."
    end

    records = template.workflowable_type.present? ? template.workflowable_type.underscore.humanize.downcase.pluralize : "records"
    journey = template.journey? ? " New #{records} will have no journey at all — no step bar and no task reminders." : ""
    rules = template.workflow_auto_assignment_rules.size
    inert = rules.positive? ? " Its #{pluralize(rules, 'auto-assignment rule')} will stop assigning it (they are kept, not deleted)." : ""

    "\"#{template.name}\" will no longer be used for new work: it will not be auto-assigned, " \
      "will not appear in the Launch Workflow picker, and cannot be launched.#{inert}#{journey} " \
      "Workflows already running on it carry on exactly as they are — they follow the snapshot taken " \
      "when they launched. You can enable it again at any time."
  end
end
