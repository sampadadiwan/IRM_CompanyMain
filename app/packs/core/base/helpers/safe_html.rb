# frozen_string_literal: true

# SafeHtml — the one place that decides which HTML text from users (or from outside systems) may
# keep when the app prints it on a page.
#
# WHY IT EXISTS
# Views used to print such text with `.html_safe` (or `Json2table…html_safe`) so users' formatting
# would show. That printed it RAW: a note, a help text, a stakeholder's name or a JSON value
# containing `<img src=x onerror=…>` ran as script for whoever opened the page
# (features/security/stored_and_reflected_xss.feature, docs/security/security_coverage_gaps_2026_11.md).
#
# WHAT IT KEEPS AND REMOVES
#   kept:    bold, italics, lists, line breaks, blockquotes, images, links (https, mailto, tel),
#            Trix attachments (figure/figcaption), and — for Json2table output — table markup
#   removed: <script>, <svg>, <iframe>, <style>, every on…= event handler, javascript:/data: links
#
# The allowlists were chosen from what the stored content actually uses (production copy,
# 2026-11-05), so existing content renders the same.
#
# Not a replacement for `html_safe` in general: Rails' own helpers and our developer-written markup
# rely on it. Use this only for text whose content a user or an outside system controls.
# Rails/OutputSafety is disabled for this module only: the strings marked html_safe here are the
# OUTPUT of Rails' safe-list sanitizer, which is exactly when marking them safe is correct.
# rubocop:disable-next Rails/OutputSafety
module SafeHtml
  module_function

  # Rails' safe-list defaults, plus Trix image attachments and underline/strike.
  RICH_TEXT_TAGS = (Rails::HTML5::SafeListSanitizer.allowed_tags.to_a + %w[figure figcaption u s]).freeze
  # Rails' defaults, plus target (help-text links open in a new tab: target="_blank").
  RICH_TEXT_ATTRIBUTES = (Rails::HTML5::SafeListSanitizer.allowed_attributes.to_a + %w[target]).freeze

  # Json2table builds <table class=… style='margin: 5px;'> with <tr>/<th>/<td> and <br/> between array
  # items. `style` is kept so the table keeps its spacing; the sanitizer scrubs the CSS itself.
  TABLE_TAGS = (RICH_TEXT_TAGS + %w[table thead tbody tfoot tr th td]).freeze
  TABLE_ATTRIBUTES = (RICH_TEXT_ATTRIBUTES + %w[style colspan rowspan]).freeze

  # Developer-built markup that may carry a user's value (FormCard titles such as
  # "Document : #{document.name}", page headers): the rich-text list plus the attributes our own markup
  # uses — inline style, id, rel, aria-label and Bootstrap's tooltip attributes. Still no event
  # handlers, scripts, javascript: links, or Turbo/Stimulus data attributes.
  UI_ATTRIBUTES = (RICH_TEXT_ATTRIBUTES + %w[style id rel aria-label data-bs-toggle data-bs-placement data-bs-title]).freeze

  SANITIZER = Rails::HTML5::SafeListSanitizer.new

  # Formatted text from a user (Trix notes, fund details, notification bodies, help text, toasts).
  #
  #   SafeHtml.rich_text('<b>Wire by Friday</b><img src="x" onerror="steal()">')
  #   # => '<b>Wire by Friday</b><img src="x">'
  def rich_text(html)
    # Step 1: nothing to show for blank text (keeps `.presence ||` fallbacks in views working)
    return "" if html.blank?

    # Step 2: keep the allowed formatting, drop everything that can run
    SANITIZER.sanitize(html.to_s, tags: RICH_TEXT_TAGS, attributes: RICH_TEXT_ATTRIBUTES).html_safe
  end

  # A title or header our code builds with HTML around a user's value, e.g. FormCard's
  # "<i class='ti ti-pencil'></i> Document : #{document.name}". Keeps the icons, links and tooltips;
  # a name like `<img src=x onerror=…>` loses its handler.
  def ui_markup(html)
    return "" if html.blank?

    SANITIZER.sanitize(html.to_s, tags: RICH_TEXT_TAGS, attributes: UI_ATTRIBUTES).html_safe
  end

  # A Json2table HTML table built from data whose values may hold user text.
  #
  # Why: Json2table does not escape anything — it builds "<td>#{value}</td>" — so a value like
  # `<img src=x onerror=…>` in an audited JSON field, a KYC response or a notification's params ran
  # as script. Sanitizing its output keeps the table (and any harmless formatting inside a value,
  # e.g. a Trix note shown in the audit trail) and drops the script.
  #
  #   SafeHtml.json_table({ "Name" => "<img src=x onerror=steal()>" })
  #   # => "<table …><tr><th>Name</th><td><img src=\"x\"></td></tr></table>"
  #
  # @param builder [Symbol] :get_html_table (JSON string or Hash) or :create_table (Hash / Array)
  def json_table(data, options = JsonTable::TABLE_OPTIONS, builder: :get_html_table)
    # Step 1: let Json2table build the table exactly as before
    html = Json2table.public_send(builder, data, options)

    # Step 2: keep the table markup, drop anything executable that came in through a value
    SANITIZER.sanitize(html.to_s, tags: TABLE_TAGS, attributes: TABLE_ATTRIBUTES).html_safe
  end
end
