# frozen_string_literal: true

# View helpers for the Support Console thread (support_console/_message).
module SupportConsoleHelper
  # Matches the closing section SupportConsoleClientBrief asks every answer to end with.
  SOURCES_HEADING = /\A\s*where this comes from\s*:?\s*\z/i

  # X24 — answers quote client data, which a planted prompt can steer. So, unlike the chat panel's
  # cleaner (MarkdownHelper), nothing here loads by itself or reaches into the page: no img/canvas
  # (a remote image would send data out on render), no id/class (could clobber Turbo targets), no
  # data-* (could attach a Stimulus controller). Links stay, but only http(s) and opened on a click.
  ANSWER_TAGS = %w[h1 h2 h3 h4 h5 h6 p a strong em del br hr ul ol li table thead tbody tr th td pre code blockquote].freeze
  ANSWER_ATTRIBUTES = %w[href title].freeze

  # Renders an answer's markdown with its "Where this comes from" section folded into a
  # collapsed <details>, so the explanation reads first and the citations are one click away.
  # Answers without that section (or still streaming before it) render unchanged.
  #
  # @param text [String] the answer's markdown
  # @return [ActiveSupport::SafeBuffer]
  def support_console_answer_html(text)
    html = answer_markdown_html(text)
    fragment = Nokogiri::HTML5.fragment(html.to_s)

    # The section's heading: a markdown heading, or a paragraph that is only that text (often bold).
    heading = fragment.children.find do |node|
      node.element? && node.name.match?(/\A(h[1-6]|p)\z/) && node.text.match?(SOURCES_HEADING)
    end
    return html unless heading

    # Everything after the heading belongs to the section — the brief puts it last.
    body = []
    node = heading.next_sibling
    while node
      body << node
      node = node.next_sibling
    end
    return html if body.none? { |n| n.element? || n.text.strip.present? }

    details = Nokogiri::XML::Node.new("details", fragment.document)
    details["class"] = "sc-sources mt-3"
    summary = Nokogiri::XML::Node.new("summary", fragment.document)
    summary.inner_html = '<i class="ti ti-file-code me-1"></i>Where this comes from'
    details.add_child(summary)
    wrap = Nokogiri::XML::Node.new("div", fragment.document)
    wrap["class"] = "sc-sources-body"
    body.each { |n| wrap.add_child(n) }
    details.add_child(wrap)
    heading.replace(details)

    # The input was already sanitized by answer_markdown_html; only our own fixed markup was added.
    fragment.to_html.html_safe # rubocop:disable Rails/OutputSafety
  end

  private

  # @param text [String] the answer's markdown
  # @return [ActiveSupport::SafeBuffer] HTML with only ANSWER_TAGS / ANSWER_ATTRIBUTES (X24)
  def answer_markdown_html(text)
    scrubber = Rails::Html::PermitScrubber.new
    scrubber.tags = ANSWER_TAGS
    scrubber.attributes = ANSWER_ATTRIBUTES
    fragment = Nokogiri::HTML5.fragment(sanitize(markdown_to_html(text).to_s, scrubber: scrubber))
    fragment.css("a").each do |link|
      # Anything but an absolute http(s) link becomes its text.
      next link.replace(link.text) unless link["href"].to_s.match?(%r{\Ahttps?://}i)

      link["target"] = "_blank"
      link["rel"] = "noopener noreferrer nofollow"
    end
    fragment.to_html.html_safe # rubocop:disable Rails/OutputSafety
  end
end
