# frozen_string_literal: true

# The one sanitizer for AI Portfolio Report HTML: section content (content_html, content_html_with_web)
# and the collated report (collated_report_html). Applied where that HTML is stored (before_save on
# AiReportSection and AiPortfolioReport), where it is rendered with html_safe (show, collated report,
# PDF and DOCX exports - which also covers rows stored before this existed), and where it is returned
# as JSON for the editor (toggle_web_search, add_content, regenerate).
#
# Same pattern as MarkdownHelper#markdown_to_html: an explicit Rails::Html::PermitScrubber.
#
# Kept: what reports legitimately contain - headings, paragraphs, inline formatting, lists, tables,
# blockquotes, web-source links, inline style (Loofah scrubs the CSS value itself) and the chart
# placeholders' data-chart-id / data-chart-config / data-chart-type.
# Stripped: img, iframe, object, link, script, style, event handlers (on*), javascript: URLs. The HTML
# handed to pandoc / wkhtmltopdf has therefore nothing for them to fetch.
#
# @see docs/security/security_review_2026_10.md (C3 - AI Portfolio Reports)
module AiReportHtml
  # C3-7, C3-H - the elements a report section or collated report is built from.
  ALLOWED_TAGS = %w[
    h1 h2 h3 h4 h5 h6
    p div span br hr
    strong b em i u s strike del ins sub sup small mark code pre
    ul ol li dl dt dd
    table caption thead tbody tfoot tr th td colgroup col
    blockquote a
  ].freeze

  # C3-H - layout and link attributes, plus the three chart placeholder attributes the editor,
  # the collated view and the exports read back. contenteditable keeps chart placeholders
  # non-editable in the section editor (it carries no script).
  ALLOWED_ATTRIBUTES = %w[
    style class id href title target rel colspan rowspan width contenteditable
    data-chart-id data-chart-config data-chart-type
  ].freeze

  # C3-7 - removed together with their content. Any other element outside ALLOWED_TAGS is unwrapped
  # (its text kept); these are dropped whole, so script source or a style sheet never resurfaces as
  # page text. button / canvas are the editor's chart chrome, re-created by renderAllCharts on load.
  DROPPED_WITH_CONTENT = %w[
    script style iframe object embed noscript template
    button canvas form input select textarea
  ].freeze

  # PermitScrubber with the report allow-lists, dropping DROPPED_WITH_CONTENT subtrees whole.
  class Scrubber < Rails::Html::PermitScrubber
    def initialize
      super
      # Allow-lists above; everything else is scrubbed
      self.tags = ALLOWED_TAGS
      self.attributes = ALLOWED_ATTRIBUTES
    end

    protected

    # Disallowed node: drop it with its content when listed, else unwrap it as PermitScrubber does.
    def scrub_node(node)
      return super unless DROPPED_WITH_CONTENT.include?(node.name)

      node.remove
      STOP
    end
  end

  # Sanitizes report HTML.
  #
  # @param html [String, nil] stored or submitted report HTML
  # @return [String, nil] sanitized HTML as a plain String (blank input returned as is)
  def self.sanitize(html)
    # Nothing to scrub
    return html if html.blank?

    # Scrub with a fresh scrubber (it holds no per-call state, but stays cheap and thread-safe)
    sanitized = ActionController::Base.helpers.sanitize(html.to_s, scrubber: Scrubber.new)
    # Plain String, not a SafeBuffer: callers decide where it is output-safe
    String.new(sanitized.to_s)
  end
end
