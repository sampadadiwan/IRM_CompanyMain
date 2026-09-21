# LP CRM MVP (docs/modules/investors/lp_relationship_crm_alt_mvp_prd.md):
# A note/task stays owned by the Investor (the LP-level timeline is unchanged),
# but can additionally point at the person at the LP it involved — the "touch
# point", an InvestorAccess record. An access belongs to exactly one investor,
# so each contact's note/task history is cleanly scoped to that stakeholder.
class AddTouchPointToNotesAndTasks < ActiveRecord::Migration[8.1]
  def change
    # Nullable on purpose: most existing notes/tasks (and any not about a specific
    # person) have no touch point. Indexed for the "everything with this person"
    # filter on the notes/tasks lists.
    add_column :notes, :touch_point_id, :bigint unless column_exists?(:notes, :touch_point_id)
    add_index :notes, :touch_point_id unless index_exists?(:notes, :touch_point_id)

    add_column :tasks, :touch_point_id, :bigint unless column_exists?(:tasks, :touch_point_id)
    add_index :tasks, :touch_point_id unless index_exists?(:tasks, :touch_point_id)
  end
end
