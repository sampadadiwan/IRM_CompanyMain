class KpiPercentageChangeJob < ApplicationJob
  queue_as :low

  def perform(entity_id, user_id)
    entities = if entity_id.nil?
                 Entity.startups
               else
                 [Entity.find(entity_id)]
               end

    recompute_percentage_change(entities, user_id)
  end

  def recompute_percentage_change(entities, user_id)
    entities.each do |entity|
      entity.kpis.joins(:kpi_report).order("kpi_report.as_of ASC").group_by { |x| [x.name, x.kpi_report.period, x.owner_id, x.kpi_report.tag_list] }.each do |key, kpis|
        msg = "Recomputing percentage change for #{key} for #{entity.name} : #{kpis.length} kpis"
        Rails.logger.debug msg
        send_notification(msg, user_id, :info)
        begin
          Kpi.recompute_percentage_change(kpis)
        rescue StandardError => e
          Rails.logger.error "Error recomputing percentage change for #{key} for #{entity.name}: #{e.message}"
          send_notification("Error recomputing percentage change for #{key} for #{entity.name}: #{e.message}", user_id, :error)
          next
        end
      end
      send_notification("Kpi percentage changes recomputed for #{entity.name}", user_id, :success)
    end
  end
end
