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
      # No .order here on purpose: sorting kpis by the joined kpi_reports.as_of can't be satisfied
      # by any index on kpis (the ORDER BY column lives on the other side of the join, confirmed
      # via EXPLAIN + FORCE INDEX - MySQL filesorts regardless), and it was dead weight anyway -
      # group_by doesn't care about input order, and Kpi.recompute_percentage_change re-sorts each
      # group by kpi_report.as_of itself.
      #
      # .joins stays: it drops any kpi whose report is missing, which would otherwise make
      # x.kpi_report nil and raise NoMethodError in the group_by key below. .preload (not
      # .includes) then loads kpi_report via a separate narrow query, avoiding an N+1 on the
      # period/tag_list calls in the group_by key without turning the join into a wide
      # eager_load - same reasoning as KpiCumulative#fetch_related_monthly_kpis.
      Kpi.where(entity_id: port_co.entity_id, portfolio_company_id: port_co.id).approved.joins(:kpi_report).preload(:kpi_report).group_by { |x| [x.name, x.kpi_report.period, x.owner_id, x.kpi_report.tag_list] }.each do |key, kpis|
        msg = "Recomputing percentage change for #{key} for #{port_co.name} : #{kpis.length} kpis"
        Rails.logger.debug msg
        send_notification(msg, user_id, :info)
        begin
          Kpi.recompute_percentage_change(kpis)
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
