require "nokogiri"
require "zlib"

# Shared Markdown resolution and rendering for the Markdown trees under docs/.
#
# Three controllers render Markdown off disk: the signed-in guide browser
# (UserGuidesController), the public, login-less guide pages
# (PublicGuidesController) and the staff-only internal docs viewer
# (InternalDocsController). The renderer options and the directory-traversal
# guard live here rather than being duplicated — a divergence in either would be
# a security or a formatting bug depending on which copy drifted.
module WithGuideRendering
  extend ActiveSupport::Concern

  # Matches the heading text guides use to introduce their FAQ section:
  # "Frequently Asked Questions", "Frequently Asked Questions (Support Team)",
  # "FAQ", "FAQs" — all present verbatim across docs/user_guides/**/*.md.
  # Leading non-letters are skipped so numbered ("8. FAQ", "16. Frequently Asked
  # Questions") and emoji ("❓ FAQ") headings are recognised too; a heading that only
  # mentions FAQ later ("AI Governance & Compliance FAQ") is still not one.
  FAQ_HEADING = /\A[^\p{L}]*(Frequently Asked Questions|FAQs?)\b/i

  # Root of the Markdown sources for the guide controllers. Every path resolved
  # by this concern is verified to sit underneath #guides_root, which defaults
  # to this constant.
  GUIDES_ROOT = Rails.root.join("docs/user_guides").freeze

  private

  # The directory every resolved path must sit inside. Overridable so a
  # controller serving a different tree (InternalDocsController serves all of
  # docs/) reuses this traversal guard instead of writing a second one.
  #
  # @return [Pathname]
  def guides_root
    GUIDES_ROOT
  end

  # Resolves a guide id ("kpi_upload_user_guide", "agents/esign_monitor_agent_user_guide")
  # to an on-disk path, refusing anything that escapes #guides_root.
  #
  # @param raw_id [String] guide id from the URL, with or without a .md suffix
  # @return [Pathname, nil] the readable guide path, or nil if missing/out of bounds
  def resolve_guide_path(raw_id)
    id = raw_id.to_s.sub(/\.md$/i, "")
    # cleanpath collapses any ".." segments so the start_with? check below cannot
    # be walked past with a crafted id.
    path = guides_root.join("#{id}.md").cleanpath
    return nil unless path.to_s.start_with?("#{guides_root}/")
    return nil unless File.exist?(path)

    path
  end

  # @param path [Pathname] a path already vetted by resolve_guide_path
  # @return [ActiveSupport::SafeBuffer] rendered HTML for the .ai-md container
  def render_guide_markdown(path)
    renderer = Redcarpet::Render::HTML.new(hard_wrap: true, filter_html: true, with_toc_data: true)
    markdown = Redcarpet::Markdown.new(renderer, autolink: true, tables: true,
                                                 fenced_code_blocks: true, lax_spacing: true,
                                                 space_after_headers: true)
    doc = Nokogiri::HTML::DocumentFragment.parse(markdown.render(File.read(path)))
    strip_redundant_hero_intro(doc)
    faq = database_faq_for(path)
    replace_faq_sections(doc, Nokogiri::HTML::DocumentFragment.parse(markdown.render(faq.markdown))) if faq&.any?
    wrap_faq_section(doc)
    anchor_database_faq_entries(doc, faq.entries) if faq&.any?
    doc.to_html.html_safe
  end

  # Audience whose FAQ entries this controller shows. PublicGuidesController overrides it.
  #
  # @return [String] "signed_in" or "public"
  def faq_audience
    "signed_in"
  end

  # FAQs managed in FAQ Manager (FaqEntry) take over from a guide's Markdown FAQ once the guide
  # has at least one published entry. Only guides under docs/user_guides have them.
  #
  # @param path [Pathname]
  # @return [FaqSectionRenderer, nil]
  def database_faq_for(path)
    return nil unless path.to_s.start_with?("#{GUIDES_ROOT}/")

    FaqSectionRenderer.new(path.relative_path_from(GUIDES_ROOT).to_s.delete_suffix(".md"), audience: faq_audience)
  end

  # Removes every Markdown FAQ section and inserts the database one before "Related Guides"
  # (or at the end). The inserted heading is marked so its entries can be given anchors.
  #
  # @param doc [Nokogiri::HTML::DocumentFragment] mutated in place
  # @param faq_doc [Nokogiri::HTML::DocumentFragment] the rendered database FAQ section
  def replace_faq_sections(doc, faq_doc)
    doc.css("h1, h2, h3, h4, h5, h6").select { |h| h.text.strip.match?(FAQ_HEADING) }.each do |heading|
      level = heading.name[1..].to_i
      node = heading.next_sibling
      heading.remove
      while node && !(node.element? && node.name.match?(/\Ah[1-6]\z/) && node.name[1..].to_i <= level)
        following = node.next_sibling
        node.remove
        node = following
      end
    end
    faq_doc.at_css("h2")["data-faq-source"] = "database"
    related = doc.css("h1, h2").find { |h| h.text.strip.match?(/\A[^\p{L}]*Related Guides\b/i) }
    related ? related.add_previous_sibling(faq_doc) : doc.add_child(faq_doc)
  end

  # Gives each database FAQ accordion item an id ("faq-<id>") so the chatbot can link to it.
  #
  # @param doc [Nokogiri::HTML::DocumentFragment]
  # @param entries [Array<FaqEntry>] in the order they were rendered
  def anchor_database_faq_entries(doc, entries)
    heading = doc.at_css('h2[data-faq-source="database"]')
    details = []
    node = heading&.next_element
    while node && node.name != "h2" && node.name != "h1"
      details.concat(node.css("details").to_a) if node.name == "div"
      node = node.next_element
    end
    details.zip(entries).each { |detail, entry| detail["id"] = "faq-#{entry.id}" if entry }
  end

  # Removes the guide's own "# Title" and the intro paragraph directly under it.
  # UserGuidesController#show and PublicGuidesController#show already lift both
  # into the hero (@title / @lede, built from #guide_title / #first_content_line)
  # — see docs/user_guides/ai_features_user_guide.md:1-3 for the shape every guide
  # follows — so left in place the body would repeat them verbatim right below.
  #
  # @param doc [Nokogiri::HTML::DocumentFragment] mutated in place
  def strip_redundant_hero_intro(doc)
    title = doc.at_css("h1")
    return unless title

    intro = title.next_element
    intro.remove if intro&.name == "p"
    title.remove
  end

  # Rewrites a guide's "## Frequently Asked Questions" section into the website's
  # own <div class="faq"><details>...</details></div> accordion markup (see
  # website_src/pages/faq.html), so it picks up caphive.css's .faq styling and
  # caphive.js's single-open behavior unmodified — no guide-specific CSS/JS needed.
  #
  # With `hard_wrap: true`, Redcarpet renders "**Question?**\nAnswer." (no blank
  # line between them, the pattern every guide uses) as ONE paragraph:
  # <p><strong>Question?</strong><br>Answer.</p> — not two separate <p> tags.
  # So each FAQ entry is a single <p> whose first child is <strong> immediately
  # followed by <br>; everything after that <br> is the answer.
  #
  # @param doc [Nokogiri::HTML::DocumentFragment] mutated in place
  def wrap_faq_section(doc)
    doc.css("h1, h2, h3, h4, h5, h6").each do |heading|
      next unless heading.text.strip.match?(FAQ_HEADING)

      level = heading.name[1..].to_i
      # One accordion per group: an FAQ split by sub-headings ("### Navigation",
      # "### What happens when I…") keeps each group's entries under its own
      # heading, instead of hoisting them all into one block under the first.
      faq_paragraph_groups_after(heading, level).each do |qa_paragraphs|
        faq_div = Nokogiri::XML::Node.new("div", doc)
        faq_div["class"] = "faq"
        qa_paragraphs.each { |p| faq_div.add_child(faq_entry(doc, p)) }

        qa_paragraphs.first.add_previous_sibling(faq_div)
        qa_paragraphs.each(&:remove)
      end
    end
  end

  # Sibling <p> elements after `heading` that match the Q/A shape, stopping at
  # the next heading of equal or shallower level (i.e. the end of this section),
  # split into groups at each deeper sub-heading in between.
  #
  # @param heading [Nokogiri::XML::Node]
  # @param level [Integer] heading's own level, e.g. 2 for <h2>
  # @return [Array<Array<Nokogiri::XML::Node>>] non-empty groups, in document order
  def faq_paragraph_groups_after(heading, level)
    groups = [[]]
    node = heading.next_element
    while node
      if node.name.match?(/\Ah[1-6]\z/)
        break if node.name[1..].to_i <= level

        groups << []
      elsif node.name == "p" && faq_paragraph?(node)
        groups.last << node
      end
      node = node.next_element
    end
    groups.reject(&:empty?)
  end

  # @param p [Nokogiri::XML::Node] a <p> element
  # @return [Boolean] true if `p` is "<strong>Question?</strong><br>Answer."
  def faq_paragraph?(p)
    first = p.children.first
    first&.name == "strong" && first.next_sibling&.name == "br"
  end

  # Builds <details><summary>Question</summary><div><p>Answer</p></div></details>
  # from one FAQ <p> already confirmed to match #faq_paragraph?.
  #
  # @param doc [Nokogiri::HTML::DocumentFragment] owner document for new nodes
  # @param p [Nokogiri::XML::Node]
  # @return [Nokogiri::XML::Node] a <details> element
  def faq_entry(doc, p)
    question = p.children.first
    br = question.next_sibling
    answer_html = br.next_sibling ? p.children[(p.children.index(br) + 1)..].map(&:to_html).join : ""

    summary = Nokogiri::XML::Node.new("summary", doc)
    summary.inner_html = question.inner_html

    answer = Nokogiri::XML::Node.new("div", doc)
    answer.inner_html = "<p>#{answer_html.strip}</p>"

    details = Nokogiri::XML::Node.new("details", doc)
    details.add_child(summary)
    details.add_child(answer)
    details
  end

  # Human-readable title for a guide. Prefers the file's own "# Title" line
  # (e.g. "Two-Factor Authentication User Guide") so hero and body always agree
  # verbatim — humanizing the id alone loses punctuation the id can't carry
  # (compare id "two_factor_authentication_user_guide" vs. the file's actual
  # "Two-Factor" hyphen). Falls back to id humanization when no path is given
  # or the file has no leading heading.
  #
  # @param raw_id [String] guide id from the URL
  # @param path [Pathname, nil] resolved guide path, if already available
  # @return [String]
  def guide_title(raw_id, path = nil)
    heading = path && first_heading_line(path)
    return heading.gsub(/ User Guide\z/i, "") if heading

    raw_id.to_s.sub(/\.md$/i, "").split("/").last.humanize.titleize.gsub(/ User Guide$/i, "")
  end

  # The file's first non-blank line, if it is a "# " H1 heading.
  #
  # @param path [Pathname]
  # @return [String, nil] heading text with the "# " marker stripped, or nil
  def first_heading_line(path)
    first_line = File.foreach(path).lazy.map(&:strip).reject(&:empty?).first
    return nil unless first_line&.start_with?("# ")

    first_line.sub(/\A#\s+/, "")
  end

  # A guide's own opening line — every guide is written with a one-line H1 title
  # followed immediately by a sentence stating what the guide covers and who it's
  # for (see docs/user_guides/entities_user_guide.md:3 for a representative
  # example). That's the guide's "key idea", so it's what the show page's hero
  # lede is built from, not a generic "here's a guide" placeholder — same idea as
  # how a website article's hero states the piece's actual argument.
  #
  # @param path [Pathname] a path already vetted by resolve_guide_path
  # @return [String, nil] the first paragraph line, or nil if the file is empty/all-headings
  def first_content_line(path)
    File.read(path).split("\n")
        .reject { |line| line.strip.empty? || line.start_with?("#") || line.start_with?("---") }
        .first
  end

  # Strips the handful of inline Markdown constructs guide openings actually use
  # (bold, italic, inline code, links) so #first_content_line's result can sit in
  # a hero .lede as plain text — the hero isn't rendered through Redcarpet like
  # the guide body is, so **entity** would otherwise show up literally asterisked.
  #
  # @param text [String, nil]
  # @return [String, nil]
  def strip_inline_markdown(text)
    return text if text.nil?

    text.gsub(/\*\*(.+?)\*\*/, '\1')
        .gsub(/(?<!\*)\*([^*]+?)\*(?!\*)/, '\1')
        .gsub(/`(.+?)`/, '\1')
        .gsub(/\[(.+?)\]\([^)]*\)/, '\1')
  end

  # Website-style tinted hero background (see .tint-* in caphive.css) for a guide's
  # show page — mirrors how the website itself colors each product page (white for
  # Funds, orange for Deals & Secondaries, black for AI Agents) instead of every
  # guide sharing one flat background.
  #
  # A subdirectory group gets its own fixed tint so every guide in it matches (the
  # "Agents" folder mirrors the website's own AI Agents black, for instance).
  # Ungrouped guides rotate deterministically through the rest, keyed off the guide
  # id via CRC32 rather than Ruby's String#hash — the latter is randomized per
  # process, which would make a guide's color flip on every server restart.
  GROUP_HERO_TINTS = { "Agents" => "tint-black" }.freeze
  DEFAULT_HERO_TINTS = %w[tint-orange tint-black tint-cream].freeze

  # @param raw_id [String] guide id from the URL, e.g. "agents/esign_monitor_agent_user_guide"
  # @param group_label [String, nil] the humanized group name, if any (see #show)
  # @return [String] one of caphive.css's .tint-* classes
  def hero_tint_for(raw_id, group_label = nil)
    GROUP_HERO_TINTS[group_label] || DEFAULT_HERO_TINTS[Zlib.crc32(raw_id.to_s) % DEFAULT_HERO_TINTS.length]
  end
end
