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
    @audiences = audience.to_s == "public" ? %w[public] : FaqEntry::AUDIENCES
  end

  # @return [Array<FaqEntry>] in display order (group order, then position)
  def entries
    @entries ||= FaqEntry.published.where(guide_key: @guide_key, audience: @audiences)
                         .order(Arel.sql(FaqEntry.group_order_sql), :position, :id).to_a
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
