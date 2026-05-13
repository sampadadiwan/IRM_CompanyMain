class AddChartHeightToAgentCharts < ActiveRecord::Migration[7.0]
  def change
    # nil means "use the Stimulus controller's JS default (420 px)".
    # Storing nil rather than a hardcoded default keeps old rows unaffected
    # and makes it easy to distinguish "user set a height" vs "not configured".
    add_column :agent_charts, :chart_height, :integer, default: nil
  end
end
