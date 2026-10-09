# An on/off switch for a workflow template, so a journey or approval chain can be retired without
# deleting it (a template that has ever been assigned or launched cannot be deleted — FKs from
# workflow_assignments and workflow_instances).
#
# Disabled means "never used for new work": no auto-assignment, no launch, not offered in the
# launch picker. Workflows already running are unaffected — they evaluate from the snapshot taken
# at launch, not from the live template.
#
# Defaults to true so every existing template keeps working exactly as it does today.
class AddEnabledToWorkflowTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :workflow_templates, :enabled, :boolean, null: false, default: true,
                                              comment: "False stops the template being assigned or launched on new records; " \
                                                       "workflows already running keep going"
  end
end
