class AddLatestToSupportAgentReports < ActiveRecord::Migration[7.2]
  def up
    add_column :support_agent_reports, :latest, :boolean, default: false, null: false

    # Backfill: mark the most-recently updated report per (owner, support_agent) pair
    execute <<~SQL
      UPDATE support_agent_reports sar
      INNER JOIN (
        SELECT MAX(updated_at) AS max_updated_at, owner_id, owner_type, support_agent_id
        FROM support_agent_reports
        GROUP BY owner_id, owner_type, support_agent_id
      ) latest_rows
        ON sar.owner_id        = latest_rows.owner_id
       AND sar.owner_type      = latest_rows.owner_type
       AND sar.support_agent_id = latest_rows.support_agent_id
       AND sar.updated_at      = latest_rows.max_updated_at
      SET sar.latest = TRUE
    SQL

    # Composite index covering (owner_type, owner_id, latest) for fast per-owner latest lookups
    add_index :support_agent_reports,
              %i[owner_type owner_id latest],
              name: "idx_support_agent_reports_owner_latest"
  end

  def down
    remove_index :support_agent_reports, name: "idx_support_agent_reports_owner_latest"
    remove_column :support_agent_reports, :latest
  end
end
