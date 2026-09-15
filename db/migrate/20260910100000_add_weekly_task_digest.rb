# Weekly Task Digest (docs/product/weekly_task_digest_prd.md).
#
# Two parts:
#
# 1. entity_settings.weekly_task_digest_enabled — the per-entity opt-in. Defaults to
#    false so deploying the feature sends nothing until a fund is explicitly enabled.
#
# 2. Two indexes on tasks. The table indexes entity_id, status, owner and the foreign
#    keys, but NOTHING on due_date or completed_on — and each of the three digest
#    section queries filters on one of them alongside entity_id and completed.
#
#    Column order follows the predicates: entity_id and completed are equality tests
#    so they lead, due_date is the range predicate and comes last.
#
#    These do NOT speed up Task.digest_counts. That query keeps all six of its
#    predicates inside SELECT-list CASE expressions, so it reads every row the policy
#    scope matches whatever indexes exist — and for a company admin the scope is
#    `entity_id = ? OR for_entity_id = ?`, which cannot drive a leading-entity_id index
#    anyway. The aggregate is one pass over the tenant's tasks by design; these indexes
#    are for the row queries that follow it.
#
#    These also serve the existing board/list due-date quick filters
#    (Task.due_filter_range) and Task.stat_counts, which scan the same columns today
#    with nothing behind them.
class AddWeeklyTaskDigest < ActiveRecord::Migration[8.1]
  DUE_INDEX = "index_tasks_on_entity_completed_due_date".freeze
  COMPLETED_ON_INDEX = "index_tasks_on_entity_completed_on".freeze

  def change
    add_column :entity_settings, :weekly_task_digest_enabled, :boolean, default: false, null: false

    add_index :tasks, %i[entity_id completed due_date], name: DUE_INDEX
    add_index :tasks, %i[entity_id completed_on], name: COMPLETED_ON_INDEX
  end
end
