class KpiAnalystJob < ApplicationJob
  queue_as :low
  MODEL = 'gemini-2.5-flash-preview-04-17'.freeze

  def perform(current_kpi_report_id, prev_kpi_report_id, user_id)
    Chewy.strategy(:sidekiq) do
      current_kpi_report = KpiReport.find(current_kpi_report_id)
      prev_kpi_report = KpiReport.find(prev_kpi_report_id)
      user = User.find(user_id)
      analyze_kpis(current_kpi_report, prev_kpi_report, user)
    end
  end

  def analyze_kpis(current_kpi_report, prev_kpi_report, user)
    chat = Chat.create(user_id: user.id, entity_id: user.entity_id, model_id: MODEL, owner: current_kpi_report, name: "KPI Analysis")
    # Set the system message
    chat.with_instructions("You are an amazing financial analyst working in an AIF, and can analyze portfolio company data to produce insightful and comprehensive analyst notes. You will generally format your analyst note in tables.")

    # Get the kpis from the report
    current_kpis = current_kpi_report.kpis.as_json(only: %i[name display_value])

    if prev_kpi_report.present?
      prev_kpis = prev_kpi_report.kpis.as_json(only: %i[name display_value])

      #  Craft the query to the LLM
      query = "Generate an Analyst note from the following KPIs from this period <CurrentPeriodKPIs> #{current_kpis} </CurrentPeriodKPIs> and compare it with the KPIs from the previous period <PreviousPeriodKPIs> #{prev_kpis} </PreviousPeriodKPIs> . Provide insights and recommendations as bullet points with the related numbers. Also generate some key questions to ask the portfolio company based on the analysis."
    else
      #  Craft the query to the LLM
      query = "Analyze the following KPIs from this period <CurrentPeriodKPIs> #{current_kpis} </CurrentPeriodKPIs> . Provide insights and recommendations as bullet points with the related numbers. Also generate some key questions to ask the portfolio company based on the analysis."
    end

    response = chat.ask(query)
    # Save the response to the kpi report
    current_kpi_report.analysis = response.content
    current_kpi_report.save
  end
end
