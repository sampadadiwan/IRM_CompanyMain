# frozen_string_literal: true

# Renders a standalone HTML cash flow report for a single fund
# and saves it as a Document in the Fund's private Reports folder.
#
# @example
#   renderer = CashFlowReportRenderer.new(fund_result, support_agent)
#   renderer.save_to_fund_folder(fund, user_id)
#
class CashFlowReportRenderer
  REPORT_NAME = "Cash Flow Analysis"

  def initialize(fund_result, support_agent)
    @fund_result = fund_result.is_a?(Hash) ? fund_result.with_indifferent_access : fund_result
    @support_agent = support_agent
    @currency = @fund_result[:currency] || "INR"
  end

  def render
    ApplicationController.render(
      partial: "support_agents/cash_flow_fund_report_html",
      locals: {
        fund_result: @fund_result,
        currency: @currency,
        support_agent: @support_agent,
        generated_at: Time.current
      }
    )
  end

  def save_to_fund_folder(fund, user_id)
    html_content = render
    folder = private_reports_folder(fund)

    # Replace previous report (don't accumulate)
    folder.documents.where(name: REPORT_NAME).destroy_all

    tempfile = Tempfile.new(["cash_flow_report", ".html"])
    begin
      tempfile.write(html_content)
      tempfile.rewind

      folder.documents.create!(
        file: File.open(tempfile.path),
        name: REPORT_NAME,
        entity_id: fund.entity_id,
        user_id: user_id,
        orignal: true,
        download: true,
        owner_tag: "Generated"
      )
    ensure
      tempfile.close
      tempfile.unlink
    end
  end

  private

  def private_reports_folder(fund)
    fund.document_folder.children.find_by(name: "Reports", private: true) ||
      fund.document_folder.children.create!(
        name: "Reports",
        entity_id: fund.entity_id,
        private: true
      )
  end
end
