# Kanban board for tasks: a coarse workflow status (todo / in_progress / done)
# alongside the legacy `completed` boolean. `done` <=> completed=true is kept in
# sync by Task callbacks (see Task#sync_status_and_completed).
class AddStatusToTasks < ActiveRecord::Migration[8.1]
  # Table-only stand-in so the backfill doesn't depend on the Task model's
  # callbacks/validations (and survives future model changes).
  class MigrationTask < ActiveRecord::Base
    self.table_name = "tasks"
  end

  def change
    # String-backed enum per codebase convention (integer enums have proven
    # unreliable across Rails versions here — see FormType).
    add_column :tasks, :status, :string, limit: 20, default: "todo", null: false
    add_index :tasks, :status

    reversible do |dir|
      # AR-generated boolean predicate keeps this portable across MySQL (dev/prod)
      # and SQLite (test).
      dir.up { MigrationTask.where(completed: true).update_all(status: "done") }
    end
  end
end
