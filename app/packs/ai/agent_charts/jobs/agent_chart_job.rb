class AgentChartJob < ApplicationJob
  queue_as :default

  # Generates agent charts for portfolio companies.
  #
  # EXECUTION MODES:
  # - :adhoc_batch (default): Shows "Chart generated" notifications for each company and final summary
  # - :scheduled: Shows only a silent "Charts generated" message (no per-company chat completion UI)
  #
  # @param user_id [Integer] the user ID who triggered the job
  # @param agent_chart_id [Integer, nil] specific AgentChart ID to use
  # @param portfolio_company_id [Integer, nil] single portfolio company ID
  # @param portfolio_company_ids [Array<Integer>, nil] multiple portfolio company IDs
  # @param tag_list [String, Array, nil] tag filter for selecting charts/companies
  # @param execution_mode [Symbol] :adhoc_batch or :scheduled (controls notification behavior)
  def perform(user_id, agent_chart_id: nil, portfolio_company_id: nil, portfolio_company_ids: nil, tag_list: nil, execution_mode: :adhoc_batch)
    agent_chart = agent_chart_id ? AgentChart.find(agent_chart_id) : nil
    user = user_id ? User.find(user_id) : nil

    # Resolve portfolio_companies based on new plural option first
    if portfolio_company_ids.present?
      portfolio_companies = Investor.where(id: portfolio_company_ids)
    elsif portfolio_company_id
      portfolio_companies = Investor.where(id: portfolio_company_id)
    else
      portfolio_companies = get_portfolio_companies(user, portfolio_company_id: portfolio_company_id, agent_chart: agent_chart)
    end

    # Determine effective tag list:
    # 1) prefer explicit tag_list param (string or array)
    # 2) else prefer agent_chart.tag_list if present
    # 3) else build combined tag list from all portfolio_companies
    effective_tag_list =
      if tag_list.present?
        tag_list.is_a?(String) ? tag_list.split(',').map(&:strip).reject(&:blank?) : Array(tag_list).map(&:to_s).map(&:strip).reject(&:blank?)
      elsif agent_chart&.tag_list.present?
        agent_chart.tag_list.is_a?(String) ? agent_chart.tag_list.split(',').map(&:strip).reject(&:blank?) : Array(agent_chart.tag_list).map(&:to_s).map(&:strip).reject(&:blank?)
      else
        combined = Array(portfolio_companies).flat_map { |pc| pc.tag_list.to_s.split(',').map(&:strip) }
        combined = combined.map(&:presence).compact.flatten.uniq
        combined.empty? ? nil : combined
      end

    agent_charts = agent_chart ? [agent_chart] : get_agent_charts(effective_tag_list, portfolio_companies&.first)

    portfolio_companies.each do |portfolio_company|
      Rails.logger.debug { "Generating charts for Portfolio Company: #{portfolio_company.investor_name}" }
      agent_charts.each do |chart|
        Rails.logger.debug { "  Using Agent Chart: #{chart.title}" }
        chart.generate_spec!(portfolio_company_id: portfolio_company.id)
        # Only show per-company notifications for adhoc_batch mode
        if execution_mode == :adhoc_batch
          send_notification("Chart #{chart.title} generated for portfolio company #{portfolio_company.investor_name}", user_id, :success)
        end
      rescue StandardError => e
        # Always show errors, regardless of mode
        send_notification("Error generating chart #{chart.title} for portfolio company #{portfolio_company.investor_name}: #{e.message}", user_id, :error)
      end
    end

    # Send completion message based on execution mode
    if execution_mode == :scheduled
      # For scheduled runs: silent charts generation, send only a summary notification
      message = "Portfolio company agent charts generated successfully"
      send_notification(message, user_id, :success)
    else
      # For adhoc batch runs: send summary as before
      message = agent_chart ? "#{agent_chart.title} chart generation completed" : "Chart generation completed"
      send_notification(message, user_id, :success)
    end
  end

  # Get the applicable agent_charts based on portfolio_company tags
  def get_agent_charts(tag_list, portfolio_company)
    tag_list ? AgentChart.with_tag_list(tag_list).where(entity_id: portfolio_company.entity_id) : []
  end

  # Get the relevant portfolio companies based on agent_chart tags
  def get_portfolio_companies(user, portfolio_company_id:, agent_chart:)
    portfolio_companies = user.entity.investors.portfolio_companies if user
    portfolio_companies = Investor.where(id: portfolio_company_id) if portfolio_company_id
    portfolio_companies = portfolio_companies.with_tag_list(agent_chart.tag_list.split(",").map(&:strip)) if agent_chart
    portfolio_companies
  end
end
