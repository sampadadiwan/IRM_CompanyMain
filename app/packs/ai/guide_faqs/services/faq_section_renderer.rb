# frozen_string_literal: true

# Builds a guide page's FAQ section from published FaqEntry rows.
#
# It emits Markdown in exactly the shape the hand-written guide FAQs used ("## Frequently
# Asked Questions", "### <group>", "**Question**" with the answer on the next line), so
# WithGuideRendering#wrap_faq_section turns it into the same accordion markup and no CSS or
# JS changes are needed.
class FaqSectionRenderer
  HEADING = "Frequently Asked Questions"

  # @param guide_key [String]
  # @param audience [String] "signed_in" or "public"
  def initialize(guide_key, audience: "signed_in")
    @guide_key = guide_key
    @audiences = self.class.audiences_for(audience)
  end

  # @return [Array<FaqEntry>] in display order (group order, then position)
  def entries
    @entries ||= self.class.published_entries(@guide_key, @audiences).to_a
  end

  # Every listed guide's entries in one query, each guide's list in the same order #entries gives. For the
  # all-FAQs page (FaqCatalog), which needs every guide at once - one query, not one per guide (R5).
  # @param guide_keys [Array<String>]
  # @param audience [String] "signed_in" or "public"
  # @return [Hash{String => Array<FaqEntry>}] keyed by guide_key; a guide with no entries has no key
  def self.entries_by_guide(guide_keys, audience: "signed_in")
    published_entries(guide_keys, audiences_for(audience)).group_by(&:guide_key)
  end

  # A public reader sees only public entries; a signed-in one sees both
  def self.audiences_for(audience)
    audience.to_s == "public" ? %w[public] : FaqEntry::AUDIENCES
  end

  # Published entries for one guide key or several, in display order (group order, then position)
  def self.published_entries(guide_keys, audiences)
    FaqEntry.published.where(guide_key: guide_keys, audience: audiences)
            .order(Arel.sql(FaqEntry.group_order_sql), :position, :id)
  end

  # @return [Boolean]
  delegate :any?, to: :entries

  # @return [String] Markdown for the whole FAQ section, or "" when there are no entries
  def markdown
    return "" if entries.empty?

    body = entries.group_by(&:faq_group).map do |_group, group_entries|
      items = group_entries.map { |e| "**#{e.question.squish}**\n#{e.answer.squish}" }
      "### #{group_entries.first.group_label}\n\n#{items.join("\n\n")}"
    end
    "## #{HEADING}\n\n#{body.join("\n\n")}\n"
  end

  # @param text [String] an answer's Markdown
  # @return [ActiveSupport::SafeBuffer] the answer as HTML, for FAQ Manager previews
  def self.answer_html(text)
    renderer = Redcarpet::Render::HTML.new(filter_html: true, safe_links_only: true)
    Redcarpet::Markdown.new(renderer, autolink: true).render(text.to_s.squish).html_safe # rubocop:disable Rails/OutputSafety
  end
end
