# frozen_string_literal: true

# Provides portfolio-report-specific system prompt, pitch document context,
# and web search tools for GenericChatAgent.
# The `target` is an AiPortfolioReport.
class PortfolioChatProvider < BaseChatProvider
  # @return [String] system prompt personalised to the portfolio company and report
  def system_prompt
    report  = target
    company = report.portfolio_company

    <<~PROMPT
      You are an AI assistant helping an analyst evaluate the portfolio company: #{company.name}.

      Analyst:     #{analyst&.name || 'Unknown'}
      Report Date: #{report.report_date}
      Date:        #{Date.current.strftime('%d %b %Y')}

      The context below contains extracted text from the company's pitch documents
      (pitch deck, financials, product overview, etc.).

      Your role:
      - Answer questions about the company based on the pitch documents
      - Help the analyst extract key information, identify red flags, and form a view
      - Use the web_search tool for information not present in the documents

      Guidelines:
      - Be professional and concise
      - Always cite the document name when referencing specific information
      - If information is not in the documents, say so and optionally search the web
      - When citing web sources, include the URL in a "Sources:" section

      #{chart_rendering_prompt}
    PROMPT
  end

  # Downloads and returns pitch document text from the report's Shrine/S3 folder.
  # @return [String] formatted document context
  def build_context
    report = target
    return "No folder linked to this report." unless report.folder.present?

    FolderDocumentExtractor.extract(report.folder)
  end

  # @return [Array<WebSearchTool>]
  def tools
    [WebSearchTool.new]
  end
end
