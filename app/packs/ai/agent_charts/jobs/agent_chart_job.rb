class AgentChartJob < ApplicationJob
  queue_as :default
  def perform(agent_chart_id, user_id)
    send_notification("Regenerating chart...", user_id)
    chart = AgentChart.find(agent_chart_id)
    begin
      chart.generate_spec!
    rescue StandardError => e
      send_notification("Error regenerating chart #{chart.title}: #{e.message}", user_id, :error)
      return
    end
    send_notification("Agent chart #{chart.title} regenerated", user_id, :success)
  end
end
