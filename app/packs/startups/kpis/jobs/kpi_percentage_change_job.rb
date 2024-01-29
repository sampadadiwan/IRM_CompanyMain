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
      entity.kpis.all.group_by { |x| "#{x.name}-#{x.period}" }.each do |kpi_name_period, kpis|
        send_notification("Recomputing percentage change for #{kpi_name_period} for #{entity.name}", user_id, :info)
        kpis.first&.recompute_percentage_change
      end
      send_notification("Kpi percentage changes recomputed for #{entity.name}", user_id, :success)
    end
  end
end
