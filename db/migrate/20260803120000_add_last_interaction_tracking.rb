# The deals grid used to sort by DealInvestor#updated_at, kept fresh by
# `belongs_to :owner, touch: true` on Note and Task. That reads the system clock —
# when the row was typed in — but the client bulk-uploads historical notes that each
# carry their own "On" date, and wants the grid to reflect when the interaction
# actually happened. So the sort key becomes a user-asserted date instead.
class AddLastInteractionTracking < ActiveRecord::Migration[8.1]
  def up
    add_column :deal_investors, :last_interaction_date, :date unless column_exists?(:deal_investors, :last_interaction_date)
    add_column :tasks, :completed_on, :date unless column_exists?(:tasks, :completed_on)

    # The default order is always scoped to one deal.
    add_index :deal_investors, %i[deal_id last_interaction_date] unless index_exists?(:deal_investors, %i[deal_id last_interaction_date])

    backfill_completed_on
    backfill_last_interaction_date_from_notes
    backfill_last_interaction_date_from_tasks
  end

  def down
    remove_index :deal_investors, %i[deal_id last_interaction_date] if index_exists?(:deal_investors, %i[deal_id last_interaction_date])
    remove_column :deal_investors, :last_interaction_date if column_exists?(:deal_investors, :last_interaction_date)
    remove_column :tasks, :completed_on if column_exists?(:tasks, :completed_on)
  end

  private

  # Already-completed tasks have no record of *when* they were completed. updated_at
  # is the only signal available, and it is right for the common case (the last write
  # to a completed task was the completion itself).
  def backfill_completed_on
    execute <<~SQL.squish
      UPDATE tasks
      SET completed_on = DATE(updated_at)
      WHERE completed = 1 AND completed_on IS NULL
    SQL
  end

  def backfill_last_interaction_date_from_notes
    execute <<~SQL.squish
      UPDATE deal_investors di
      JOIN (
        SELECT owner_id, MAX(`on`) AS max_on
        FROM notes
        WHERE owner_type = 'DealInvestor' AND `on` IS NOT NULL
        GROUP BY owner_id
      ) n ON n.owner_id = di.id
      SET di.last_interaction_date = n.max_on
    SQL
  end

  # GREATEST so a completed task can only raise the value the notes pass set, never
  # lower it. GREATEST returns NULL if any argument is NULL, hence the COALESCE.
  def backfill_last_interaction_date_from_tasks
    execute <<~SQL.squish
      UPDATE deal_investors di
      JOIN (
        SELECT owner_id, MAX(completed_on) AS max_completed_on
        FROM tasks
        WHERE owner_type = 'DealInvestor' AND completed = 1 AND completed_on IS NOT NULL
        GROUP BY owner_id
      ) t ON t.owner_id = di.id
      SET di.last_interaction_date =
        GREATEST(COALESCE(di.last_interaction_date, t.max_completed_on), t.max_completed_on)
    SQL
  end
end
