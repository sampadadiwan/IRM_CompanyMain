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

  # The answer layout SupportConsoleClientBrief asks for. A section is recognised by its heading's
  # text alone, so an answer written before the layout existed simply has no such sections.
  SUMMARY_HEADING = /\A\s*(summary|final analysis|conclusion|answer|in short)\s*:?\s*\z/i
  FIGURES_HEADING = /\A\s*(key figures|key numbers|figures|stats|statistics)\s*:?\s*\z/i
  # Kept for answers saved before Follow-ups replaced it: they still show their Questions card.
  QUESTIONS_HEADING = /\A\s*(questions|open questions|questions for you)\s*:?\s*\z/i
  FOLLOW_UPS_HEADING = /\A\s*(follow-?ups?|follow-?up questions|suggested questions|next questions)\s*:?\s*\z/i
  # The most suggested next questions shown above the composer (E44).
  MAX_FOLLOW_UPS = 3
  # "Label: value" — the shape of one Key figures bullet (the label is usually bold).
  FIGURE_ITEM = /\A\s*([^:]{1,60}?)\s*:\s*(.+)\z/m

  # A turn's status as a badge: [theme colour, icon, label]. Shared by the answer (_message) and the
  # sidebar row (_conversation), so a status reads the same in both. A completed answer has none.
  STATUS_BADGES = {
    "queued" => %w[primary ti-loader Running],
    "running" => %w[primary ti-loader Running],
    "stopped" => %w[secondary ti-player-stop Stopped],
    "failed" => ["danger", "ti-alert-circle", "Not answered"],
    "refused" => ["danger", "ti-lock", "Access ended"]
  }.freeze

  # E46 — a sidebar title: the first question without the quote marks it was often pasted with.
  #
  # @param question [String, nil]
  # @return [String]
  def support_console_conversation_title(question)
    question.to_s.squish.sub(/\A["'“‘]+/, "").sub(/["'”’]+\z/, "").presence || "New conversation"
  end

  # H15 — when a sidebar conversation last changed: the time today, the locale's date before that.
  #
  # @param time [ActiveSupport::TimeWithZone]
  # @return [String]
  def support_console_conversation_when(time)
    time.to_date == Time.zone.today ? l(time, format: :time_only) : l(time.to_date)
  end

  # Renders an answer's markdown with Bootstrap structure (H13): Summary as a card, Key figures as
  # stat cards, Questions as a list group, tables/quotes/code with Bootstrap classes, and the
  # "Where this comes from" section folded into a collapsed <details>. Follow-ups are left out;
  # the composer shows them (support_console_follow_ups). An answer without those
  # headings (E40), or still streaming before them, keeps the element-level classes only.
  #
  # X36 — the classes are added here, after the sanitizer has stripped every class the answer
  # itself carried, and are chosen only from fixed lists by element name or heading text.
  #
  # @param text [String] the answer's markdown
  # @return [ActiveSupport::SafeBuffer]
  def support_console_answer_html(text)
    fragment = Nokogiri::HTML5.fragment(answer_markdown_html(text).to_s)

    # Element-level classes first, so the sections built below carry them along.
    decorate_answer_elements(fragment)

    # Then turn each recognised section into its Bootstrap block.
    answer_sections(fragment).each do |heading, body|
      next if heading.nil?

      # H14 — follow-ups are shown once, as buttons above the composer, not in the answer.
      if follow_ups_heading?(heading)
        ([heading] + body).each(&:remove)
        next
      end
      next if body.none? { |n| n.element? || n.text.strip.present? }

      block = answer_section_block(fragment.document, heading, body)
      next unless block

      # The block takes the heading's place; the body nodes have moved into it.
      heading.replace(block)
    end

    # The input was already sanitized by answer_markdown_html; only our own fixed markup was added.
    fragment.to_html.html_safe # rubocop:disable Rails/OutputSafety
  end

  # H14 — the suggested next questions at the end of an answer, for the composer's buttons.
  # Plain text only (X37): whatever markup a bullet carried is dropped.
  #
  # @param text [String] the answer's markdown
  # @return [Array<String>] at most MAX_FOLLOW_UPS questions, in the answer's order
  def support_console_follow_ups(text)
    # A cheap text check first: the composer looks back through every completed answer, and ones
    # written before Follow-ups existed should not each be rendered and parsed on every turn.
    return [] unless text.to_s.match?(/follow-?up|suggested questions|next questions/i)

    fragment = Nokogiri::HTML5.fragment(answer_markdown_html(text).to_s)
    _heading, body = answer_sections(fragment).find { |h, _| h && follow_ups_heading?(h) }
    return [] unless body

    # Bullets as the brief asks; paragraphs when the answer wrote them that way.
    items = answer_list_items(body)
    items = body.select { |n| n.element? && n.name == "p" } if items.empty?
    items.map { |item| item.text.squish }.compact_blank.first(MAX_FOLLOW_UPS)
  end

  private

  # @param heading [Nokogiri::XML::Element]
  # @return [Boolean]
  def follow_ups_heading?(heading)
    heading.text.strip.match?(FOLLOW_UPS_HEADING)
  end

  # Bootstrap classes on the plain markdown elements, wherever they sit in the answer.
  #
  # @param fragment [Nokogiri::HTML5::DocumentFragment]
  def decorate_answer_elements(fragment)
    # One heading size for the whole answer, whatever level the markdown used.
    fragment.css("h1, h2, h3, h4, h5, h6").each { |h| h["class"] = "h6 mt-4 mb-2" }

    # Tables: the app's .table look, inside a bordered card that scrolls sideways when wide.
    fragment.css("table").each do |table|
      table["class"] = "table table-sm table-hover align-middle mb-0"
      wrap = Nokogiri::XML::Node.new("div", fragment.document)
      wrap["class"] = "card border shadow-none overflow-hidden mb-3"
      scroll = Nokogiri::XML::Node.new("div", fragment.document)
      scroll["class"] = "table-responsive"
      table.replace(wrap)
      wrap.add_child(scroll)
      scroll.add_child(table)
    end

    # Quotes read as a callout; code blocks as a shaded panel.
    fragment.css("blockquote").each { |q| q["class"] = "alert alert-info py-2 px-3 mb-3" }
    fragment.css("pre").each { |pre| pre["class"] = "bg-body-tertiary rounded-3 p-3 small mb-3" }
  end

  # Splits the answer's top-level nodes at its headings. A heading is a markdown heading, or a
  # paragraph that is only a known section title (often bold).
  # E42 — "Where this comes from" is last (the brief puts it there), so everything after it is its
  # body, its own sub-headings ("### Code", "### Lookups") included.
  #
  # @param fragment [Nokogiri::HTML5::DocumentFragment]
  # @return [Array<Array(Nokogiri::XML::Element, Array<Nokogiri::XML::Node>)>] [heading, body] pairs;
  #   the nodes before the first heading come first, with a nil heading
  def answer_sections(fragment)
    sections = [[nil, []]]
    fragment.children.each do |node|
      in_sources = sections.last[0]&.text&.match?(SOURCES_HEADING)
      if !in_sources && answer_heading?(node)
        sections << [node, []]
      else
        sections.last[1] << node
      end
    end
    sections
  end

  # @param node [Nokogiri::XML::Node]
  # @return [Boolean]
  def answer_heading?(node)
    return false unless node.element?
    return true if node.name.match?(/\Ah[1-6]\z/)

    # A paragraph counts only when it is exactly one of the layout's titles.
    node.name == "p" &&
      [SOURCES_HEADING, SUMMARY_HEADING, FIGURES_HEADING, QUESTIONS_HEADING, FOLLOW_UPS_HEADING].any? { |re| node.text.match?(re) }
  end

  # The Bootstrap block for one recognised section, or nil to leave the section as plain text.
  #
  # @param doc [Nokogiri::XML::Document]
  # @param heading [Nokogiri::XML::Element]
  # @param body [Array<Nokogiri::XML::Node>]
  # @return [Nokogiri::XML::Element, nil]
  def answer_section_block(doc, heading, body)
    title = heading.text.strip.delete_suffix(":").strip
    case title
    when SOURCES_HEADING then answer_sources_block(doc, body)
    when SUMMARY_HEADING then answer_summary_block(doc, title, body)
    when FIGURES_HEADING then answer_figures_block(doc, heading, body)
    when QUESTIONS_HEADING then answer_questions_block(doc, title, body)
    end
  end

  # "Where this comes from": collapsed, so the explanation reads first.
  def answer_sources_block(doc, body)
    details = html_node(doc, "details", "sc-sources mt-3")
    summary = html_node(doc, "summary")
    summary.inner_html = '<i class="ti ti-file-code me-1"></i>Where this comes from'
    details.add_child(summary)
    wrap = html_node(doc, "div", "sc-sources-body")
    body.each { |n| wrap.add_child(n) }
    details.add_child(wrap)
    details
  end

  # Summary / final analysis: a card with the section's own title in its header.
  def answer_summary_block(doc, title, body)
    card = html_node(doc, "div", "card shadow-sm mb-3")
    card.add_child(answer_card_header(doc, "ti-bulb", "text-primary", title))
    card_body = html_node(doc, "div", "card-body")
    body.each { |n| card_body.add_child(n) }
    card.add_child(card_body)
    card
  end

  # Key figures: one stat card per "Label: value" bullet, in NumberStatsComponent's markup.
  # E41 — bullets of another shape stay as a list under the cards; with none of that shape the
  # section stays plain text (nil).
  def answer_figures_block(doc, heading, body)
    items = answer_list_items(body)
    figures = items.filter_map do |li|
      label, value = li.text.strip.match(FIGURE_ITEM)&.captures
      [li, label, value] if label && value.present?
    end
    return nil if figures.empty?

    section = html_node(doc, "div")
    # The heading stays, so the cards are introduced like every other section — rebuilt as a
    # heading at the answer's one size, since it may have been a bold paragraph.
    title = html_node(doc, "h6", "h6 mt-4 mb-2")
    title.content = heading.text.strip
    section.add_child(title)
    row = html_node(doc, "div", "row g-0 mb-3")
    figures.each do |li, label, value|
      li.remove
      row.add_child(answer_stat_card(doc, label, value))
    end
    section.add_child(row)
    # Whatever was not a figure (an intro line, odd bullets) follows the cards; emptied lists go.
    body.each { |n| answer_list?(n) && n.element_children.none? ? n.remove : section.add_child(n) }
    section
  end

  # One Key figures card: value large, label underneath, primary accent along the top.
  def answer_stat_card(doc, label, value)
    col = html_node(doc, "div", "col-sm-6 col-lg-3 d-flex")
    card = html_node(doc, "div", "card m-2 border-top stat-card-accent border-primary shadow-sm flex-fill")
    card_body = html_node(doc, "div", "card-body")
    figure = html_node(doc, "h2", "fs-6 fw-normal mb-1")
    figure.content = value.strip
    caption = html_node(doc, "span", "card-subtitle mb-0 text-primary")
    caption.content = label.strip
    card_body.add_child(figure)
    card_body.add_child(caption)
    card.add_child(card_body)
    col.add_child(card)
    col
  end

  # Questions: a card holding a list group, one item per question, each with an Ask button.
  def answer_questions_block(doc, title, body)
    items = answer_list_items(body)
    # Questions written as paragraphs instead of bullets count too.
    items = body.select { |n| n.element? && n.name == "p" } if items.empty?
    return nil if items.empty?

    card = html_node(doc, "div", "card shadow-sm mb-3")
    card.add_child(answer_card_header(doc, "ti-help-circle", "text-info", title))
    group = html_node(doc, "ul", "list-group list-group-flush")
    items.each do |item|
      # Read before the children move: the question as plain text, for its Ask button (X38).
      question = item.text.squish
      li = html_node(doc, "li", "list-group-item d-flex gap-2")
      li.inner_html = '<i class="ti ti-help-circle text-info mt-1"></i>'
      text = html_node(doc, "div", "flex-grow-1")
      item.children.each { |c| text.add_child(c) }
      li.add_child(text)
      li.add_child(answer_ask_button(doc, question)) if question.present?
      group.add_child(li)
    end
    card.add_child(group)
    # Anything else in the section (an intro line) sits above the list.
    rest = body.reject { |n| items.include?(n) || answer_list?(n) }
    unless rest.none? { |n| n.element? || n.text.strip.present? }
      intro = html_node(doc, "div", "card-body pb-0")
      rest.each { |n| intro.add_child(n) }
      group.add_previous_sibling(intro)
    end
    # The questions' text has moved into the list group; drop the emptied lists and paragraphs.
    body.each { |n| n.remove if answer_list?(n) || items.include?(n) }
    card
  end

  # H16 — sends the question straight away (support_console_thread_controller#askNow). Only this
  # fixed button carries a data-action; the question is a plain-text attribute value, never markup.
  def answer_ask_button(doc, question)
    button = html_node(doc, "button", "btn btn-sm btn-outline-primary flex-shrink-0 align-self-start")
    button["type"] = "button"
    button["title"] = "Ask this now"
    # Its own accessible name, so it is not one more button called just "Ask".
    button["aria-label"] = "Ask: #{question}"
    button["data-action"] = "support-console-thread#askNow"
    button["data-prompt"] = question
    button.inner_html = '<i class="ti ti-arrow-up"></i>Ask'
    button
  end

  # A card header: icon + the section's title, as text (never markup from the answer). The icon
  # sits inside the h6, as in the app's other card headers, so the two line up on one centre.
  def answer_card_header(doc, icon, colour, title)
    header = html_node(doc, "div", "card-header bg-transparent")
    label = html_node(doc, "h6", "mb-0 d-flex align-items-center")
    label.inner_html = %(<i class="ti #{icon} #{colour} me-2"></i>)
    label.add_child(Nokogiri::XML::Text.new(title, doc))
    header.add_child(label)
    header
  end

  # @param body [Array<Nokogiri::XML::Node>]
  # @return [Array<Nokogiri::XML::Element>] the top-level bullets of the section's lists
  def answer_list_items(body)
    body.select { |n| answer_list?(n) }.flat_map { |list| list.element_children.select { |c| c.name == "li" } }
  end

  def answer_list?(node)
    node.element? && %w[ul ol].include?(node.name)
  end

  # @return [Nokogiri::XML::Element] a new element with an optional fixed class list
  def html_node(doc, name, css_class = nil)
    node = Nokogiri::XML::Node.new(name, doc)
    node["class"] = css_class if css_class
    node
  end

  # @param text [String] the answer's markdown
  # @return [ActiveSupport::SafeBuffer] HTML with only ANSWER_TAGS / ANSWER_ATTRIBUTES (X24)
  def answer_markdown_html(text)
    return ActiveSupport::SafeBuffer.new if text.blank?

    scrubber = Rails::Html::PermitScrubber.new
    scrubber.tags = ANSWER_TAGS
    scrubber.attributes = ANSWER_ATTRIBUTES
    # E47 — markdown_to_html renders with no_intra_emphasis, so snake_case names are not italicised.
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
