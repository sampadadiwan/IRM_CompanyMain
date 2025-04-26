class KpiAnalystJob < ApplicationJob
  queue_as :low
  MODEL = 'gemini-2.5-flash-preview-04-17'.freeze

  def perform(current_kpi_report_id, prev_kpi_report_id, user_id)
    Chewy.strategy(:sidekiq) do
      current_kpi_report = KpiReport.find(current_kpi_report_id)
      prev_kpi_report = KpiReport.find(prev_kpi_report_id)
      user = User.find(user_id)

      chat = Chat.create(user_id: user.id, entity_id: user.entity_id, model_id: MODEL, owner: current_kpi_report, name: "KPI Analysis")
      # Set the system message
      chat.with_instructions("You are an amazing financial analyst working in an AIF, and can analyze portfolio company data to produce insightful and comprehensive analyst notes. You will generally format your analyst note in tables.")

      send_notification("Analysis of KPIs started", user.id)
      analyze_kpis(current_kpi_report, prev_kpi_report, chat, user)
      send_notification("Analysis of Investor Presentation started", user.id)
      analyze_investor_presentation(current_kpi_report, chat, user)
      send_notification("Analysis of KPIs completed", user.id)
    end
  end

  def analyze_kpis(current_kpi_report, prev_kpi_report, chat, _user)
    Rails.logger.debug { "Analyzing KPIs for report #{current_kpi_report.id} and previous report #{prev_kpi_report.id}" }

    # Get the kpis from the report
    current_kpis = current_kpi_report.kpis.as_json(only: %i[name display_value])

    if prev_kpi_report.present?
      prev_kpis = prev_kpi_report.kpis.as_json(only: %i[name display_value])

      #  Craft the query to the LLM
      query = "Generate an Analyst note from the following KPIs from this period <CurrentPeriodKPIs> #{current_kpis} </CurrentPeriodKPIs> and compare it with the KPIs from the previous period <PreviousPeriodKPIs> #{prev_kpis} </PreviousPeriodKPIs>."
    else
      #  Craft the query to the LLM
      query = "Analyze the following KPIs from this period <CurrentPeriodKPIs> #{current_kpis} </CurrentPeriodKPIs>."
    end

    query += " In the first section summarize the data in a table. In the second section provide insights and recommendations as bullet points with the related numbers. In the last section generate a table of key questions to ask the portfolio company based on the analysis."

    chat.ask(query)
  end

  IP_QUESTION = "Summarize the Investor Presentation document. In section 1 clearly outline the key facts and figures from the document in tables, In section 2 present an analysis of the key facts and strategy discussed. In section 3 generate a table of key questions based on the document that need further attention. In section 4 add a table listing the risks for the company.".freeze

  def analyze_investor_presentation(current_kpi_report, chat, _user)
    Rails.logger.debug { "Analyzing Investor Presentation for report #{current_kpi_report.id}" }
    doc = current_kpi_report.documents.where("name like '%Investor Presentation%'").first
    chat.ask(IP_QUESTION, with: { pdf: doc.file_url }) if doc.present?
  end
end
