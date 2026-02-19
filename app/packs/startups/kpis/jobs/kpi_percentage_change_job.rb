class KpiPercentageChangeJob < ApplicationJob
  queue_as :low

  def perform(portfolio_company_ids, user_id)
    portfolio_companies = if portfolio_company_ids.nil?
                            Pundit.policy_scope(User.find(user_id), Investor).portfolio_companies
                          else
                            Pundit.policy_scope(User.find(user_id), Investor).portfolio_companies.where(id: portfolio_company_ids)
                          end

    recompute_percentage_change(portfolio_companies, user_id)
  end

  def recompute_percentage_change(portfolio_companies, user_id)
    portfolio_companies.each do |port_co|
      Kpi.where(entity_id: port_co.entity_id, portfolio_company_id: port_co.id).approved.joins(:kpi_report).order("kpi_report.as_of ASC").group_by { |x| [x.name, x.kpi_report.period, x.owner_id, x.kpi_report.tag_list] }.each do |key, kpis|
        msg = "Recomputing percentage change for #{key} for #{port_co.name} : #{kpis.length} kpis"
        Rails.logger.debug msg
        send_notification(msg, user_id, :info)
        begin
          Kpi.recompute_percentage_change(kpis, force: true)
        rescue StandardError => e
          Rails.logger.error "Error recomputing percentage change for #{key} for #{port_co.name}: #{e.message}"
          send_notification("Error recomputing percentage change for #{key} for #{port_co.name}: #{e.message}", user_id, :error)
          next
        end
      end
      msg = "Kpi percentage changes recomputed for #{port_co.name}"
      level = :success
      send_notification(msg, user_id, level)
    end
  end
end
