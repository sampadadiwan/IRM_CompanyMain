class AddReportIdToAgentChart < ActiveRecord::Migration[8.0]
  def change
    add_column :agent_charts, :report_id, :integer, default: nil
  end
end
