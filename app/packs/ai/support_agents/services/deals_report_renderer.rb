# frozen_string_literal: true

# Renders a standalone HTML deal fundraising report for a single deal
# and saves it as a Document in the Deal's private Reports folder.
#
# @example
#   renderer = DealsReportRenderer.new(deal_result, support_agent)
#   renderer.save_to_deal_folder(deal, user_id)
#
class DealsReportRenderer
  REPORT_NAME = "Deal Fundraising Report"

  def initialize(deal_result, support_agent)
    @deal_result   = deal_result.is_a?(Hash) ? deal_result.with_indifferent_access : deal_result
    @support_agent = support_agent
    @currency      = @deal_result[:currency] || "INR"
  end

  def render
    ApplicationController.render(
      partial: "support_agents/deals_report_html",
      locals: {
        deal_result:   @deal_result,
        currency:      @currency,
        support_agent: @support_agent,
        generated_at:  Time.current
      }
    )
  end

  def save_to_deal_folder(deal, user_id)
    html_content = render
    folder = reports_folder(deal)

    # Replace previous report — don't accumulate duplicates
    folder.documents.where(name: REPORT_NAME).destroy_all

    tempfile = Tempfile.new(["deal_report", ".html"])
    begin
      tempfile.write(html_content)
      tempfile.rewind

      folder.documents.create!(
        file:      File.open(tempfile.path),
        name:      REPORT_NAME,
        entity_id: deal.entity_id,
        user_id:   user_id,
        orignal:   true,
        download:  true,
        owner_tag: "Generated"
      )
    ensure
      tempfile.close
      tempfile.unlink
    end
  end

  private

  def reports_folder(deal)
    deal.document_folder.children.find_by(name: "Reports", private: true) ||
      deal.document_folder.children.create!(
        name:      "Reports",
        entity_id: deal.entity_id,
        private:   true
      )
  end
end
