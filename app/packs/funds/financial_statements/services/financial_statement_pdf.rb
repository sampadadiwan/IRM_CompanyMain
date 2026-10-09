# PDF download of a statement set: one section per statement (page break between), the Checks, and a
# DRAFT watermark on every page of a draft. Locked sets print their frozen figures (H19, E10).
# Rendered with headless Chrome (FerrumPdf), as the fund dashboard PDFs are.
# Worked examples H19, E10 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementPdf
  def initialize(statement)
    @statement = statement
  end

  def html
    # Rendered through the controller so the views get the app helpers (amount formatting, l)
    FinancialStatementsController.render(template: "financial_statements/pdf", layout: false,
                                         assigns: { financial_statement: @statement, fund: @statement.fund })
  end

  def render
    # Same browser setup as FundsController#dashboard's PDF
    FerrumPdf.browser(timeout: 60)
    FerrumPdf.render_pdf(html:, pdf_options: { format: :A4, print_background: true, margin_top: 0.6, margin_bottom: 0.6,
                                               margin_left: 0.5, margin_right: 0.5, display_header_footer: true,
                                               header_template: header_template, footer_template: FOOTER })
  end

  # Page numbers on every page
  FOOTER = "<div style='font-size:8px;width:100%;text-align:center;color:#888'>" \
           "Page <span class='pageNumber'></span> of <span class='totalPages'></span></div>".freeze

  private

  # H19: a draft says so in the header of every page (and in the watermark); a locked set names its lock date
  def header_template
    text = if @statement.locked?
             "#{ERB::Util.html_escape(@statement.fund.name)} — locked #{I18n.l(@statement.locked_at.to_date)}"
           else
             "DRAFT — not for distribution"
           end
    color = @statement.locked? ? "#888" : "#c00"
    "<div style='font-size:9px;width:100%;text-align:center;color:#{color}'>#{text}</div>"
  end
end
