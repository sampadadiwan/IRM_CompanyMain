class KpiExtractorService < AiAssistant
  KPI_INSTRUCTIONS = "You're a financial analyst who will be required to extract KPIs from the data provided to you. The csv document will have multiple columns with different time periods. Please extract KPIs for every roww, and every time period including Quarters (Q) and Calender Year (CY). You can ignore blank rows and columns. Examine all data in the file, and do not leave out any KPIs. Respond only with json and no other text, do not add any ```json to the output".freeze

  def self.run_ai_kpi_extraction(portfolio_company, kpi_document, overwrite_kpis: false)
    # We get a kpi_document for a portfolio_company, we need to extract the kpis and add them to the appropriate kpi report

    assistant = AiAssistant.new(nil, KPI_INSTRUCTIONS)
    assistant.add_doc_as_text(kpi_document)
    llm_response = assistant.query("Extract all the KPIs from the columns the document for all the time periods. The json you extract must have the format given in the example below.
                            {
                                :name => 'Name of the kpi extracted',
                                :date => 'Effective date of the kpi',
                                :value => 'Value of the kpi extracted',
                                :notes => 'Any notes or comments about the kpi extracted',
                            }")

    response = JSON.parse(llm_response)
    response.each do |kpi|
      as_of = KpiReport.convert_to_date(kpi["date"])
      kpi_report = KpiReport.find_or_create_by(entity_id: portfolio_company.entity_id, as_of:, user_id: 21, portfolio_company:)

      existing_kpi = kpi_report.kpis.where(name: kpi["name"]).first
      if existing_kpi
        if overwrite_kpis
          existing_kpi.update(value: kpi["value"], display_value: kpi["value"], notes: kpi["notes"])
        else
          Rails.logger.debug { "KPI #{existing_kpi} already exists, skipping" }
        end
      else
        kpi_report.kpis.create(entity_id: portfolio_company.entity_id, name: kpi["name"], value: kpi["value"], display_value: kpi["value"], notes: kpi["notes"])
      end
    end
  end
end
