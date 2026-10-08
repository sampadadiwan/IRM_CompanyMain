# Upgrades the workflow engine so a step can complete from data (system), from a single
# confirmation (acknowledge) or from votes (human, today's behaviour), and so an instance can
# remember its last evaluation. See openspec/changes/capital-call-journey/lld.md → Schema Detail.
class AddJourneyFieldsToWorkflows < ActiveRecord::Migration[8.1]
  def change
    # How a step completes, what decides it, who is chased, what it unlocks.
    # kind defaults to 0 (human) so every existing step keeps today's behaviour.
    change_table :workflow_steps, bulk: true do |t|
      t.integer :kind, null: false, default: 0,
                       comment: "How the step completes: 0=human (votes), 1=system (data check), 2=acknowledge (one confirmation)"
      t.string :check_key, limit: 100,
                           comment: "Registered check deciding a system/acknowledge step, e.g. capital_call.approve_notices"
      t.string :skip_key, limit: 100,
                          comment: "Registered check that makes the step not applicable when true"
      t.references :owner_user, foreign_key: { to_table: :users }, index: true,
                                comment: "User reminded when a system/acknowledge step stalls; NULL = the record's default owner (e.g. the call's creator)"
      t.string :unlocks, comment: "CSV of button labels this step unlocks once passed or not applicable"
      t.boolean :keep_on_regress, null: false, default: false,
                                  comment: "Keep this step's sign-offs when an undoing action moves the workflow back before it"
    end

    # Seeded journey templates keep a stable identity across admin renames
    change_table :workflow_templates, bulk: true do |t|
      t.string :system_key, limit: 50,
                            comment: "Identity of a seeded template (capital_call_full, capital_call_light) so re-seeding finds it after a rename"
      t.index %i[entity_id system_key], unique: true
    end

    # The last evaluation (a cache), when the current step started, when it last completed,
    # and whether this instance is evaluated at all (set at launch).
    change_table :workflow_instances, bulk: true do |t|
      t.boolean :evaluated, null: false, default: false,
                            comment: "True when the snapshot has a non-human step; only these are evaluated from data and ticked"
      t.json :step_results, comment: "Cache of the last evaluation per step position (status, message, link, times); never the source of truth"
      t.datetime :current_step_since, comment: "When the current step became current, stamped from the data; reminder intervals run from here"
      t.datetime :completed_at, comment: "When the instance last completed; it can reopen, and the tick stops 30 days after this"
    end
    add_index :workflow_instances, %i[evaluated status]

    # "Latest invalidated / recomputed per step" lookups on every evaluation
    add_index :workflow_state_changes, %i[workflow_instance_id step_position to_state created_at],
              name: "index_workflow_state_changes_on_instance_position_state_time"
  end
end
