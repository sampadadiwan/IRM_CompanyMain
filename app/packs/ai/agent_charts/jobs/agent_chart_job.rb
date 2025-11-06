class AgentChartJob < ApplicationJob
  queue_as :default

  def perform(user_id, agent_chart_id: nil, portfolio_company_id: nil)
    agent_chart = agent_chart_id ? AgentChart.find(agent_chart_id) : nil
    user = user_id ? User.find(user_id) : nil
    portfolio_company = portfolio_company_id ? Investor.find(portfolio_company_id) : nil

    # Validate presence of at least one of agent_chart or portfolio_company
    if agent_chart.nil? && portfolio_company.nil?
      send_notification("No agent chart or portfolio company specified for chart generation", user_id, :error)
      return
    end

    # Get relevant portfolio companies and agent charts
    portfolio_companies = get_portfolio_companies(user, portfolio_company_id: portfolio_company_id, agent_chart: agent_chart)
    agent_charts = agent_chart ? [agent_chart] : get_agent_charts(portfolio_company&.tag_list, portfolio_company)

    # Generate chart for each portfolio company and each agent chart
    portfolio_companies.each do |portfolio_company|
      Rails.logger.debug { "Generating charts for Portfolio Company: #{portfolio_company.investor_name}" }
      agent_charts.each do |chart|
        Rails.logger.debug { "  Using Agent Chart: #{chart.title}" }
        chart.generate_spec!(portfolio_company_id: portfolio_company.id)
        send_notification("Chart #{chart.title} generated for portfolio company #{portfolio_company.id}", user_id, :success)
      rescue StandardError => e
        send_notification("Error generating chart #{chart.title} for portfolio company #{portfolio_company.id}: #{e.message}", user_id, :error)
      end
    end

    message = "#{agent_chart.title} chart generation completed for all portfolio_companies with tag #{agent_chart.tag_list}" if agent_chart
    message ||= "Chart generation completed for #{portfolio_company.investor_name}" if portfolio_company

    send_notification(message, user_id, :success)
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
