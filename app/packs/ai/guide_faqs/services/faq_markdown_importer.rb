# frozen_string_literal: true

# One-time migration: reads the FAQ sections written into docs/user_guides/**/*.md and creates a
# published FaqEntry for each question (rake guide_faqs:import_markdown).
#
# Idempotent: a question that already exists for the guide is left untouched, so an entry edited
# in FAQ Manager is never overwritten. With refresh: true, entries nobody has edited in the app are
# updated to the current Markdown (rake guide_faqs:import_markdown REFRESH=1). Group sub-headings ("### Why use capital calls") map to
# FaqEntry::GROUPS by keyword; anything unrecognised becomes "troubleshooting".
class FaqMarkdownImporter
  QUESTION = /\A\*\*(.+)\*\*\s*\z/

  GROUP_RULES = [
    [/navigat|getting there|where to find|finding/i, "navigation"],
    [/what happens/i, "what_happens"],
    [/\bwhy\b|matters|benefit/i, "why"],
    [/creat|updat|manag|delet|how to|using|setting up|configur/i, "how_to"]
  ].freeze

  Result = Data.define(:created, :updated, :archived, :skipped, :errors)

  # @param verified_at [Time] recorded as each imported entry's last verification
  def initialize(verified_at: Time.zone.parse("2026-09-13"))
    @verified_at = verified_at
  end

  # @param refresh [Boolean] also bring entries that nobody has edited in the app back in line with
  #   the Markdown: update their answer and group, and archive ones whose question is no longer in
  #   the guide. "Edited in the app" means updated_by is set, which FAQ Manager always records.
  # @return [Result]
  def call(refresh: false)
    counts = Hash.new(0)
    errors = []
    Chewy.strategy(:atomic) do
      GuideCatalog.guide_keys.each do |guide_key|
        items = parse(guide_key)
        items.each { |item| import_item(guide_key, item, refresh, counts, errors) }
        archive_removed(guide_key, items, counts) if refresh
      end
    end
    Result.new(created: counts[:created], updated: counts[:updated], archived: counts[:archived],
               skipped: counts[:skipped], errors: errors)
  end

  # @param guide_key [String]
  # @return [Array<Hash>] :faq_group, :question, :answer for each FAQ entry in the guide
  def parse(guide_key)
    lines = File.readlines(GuideCatalog::ROOT.join("#{guide_key}.md"), chomp: true)
    items = []
    faq_level = nil
    group = "troubleshooting"

    lines.each_with_index do |line, idx|
      if (heading = line.match(/\A(#+)\s+(.*)/))
        level = heading[1].size
        if heading[2].strip.match?(WithGuideRendering::FAQ_HEADING)
          faq_level = level
          group = "troubleshooting"
        elsif faq_level && level <= faq_level
          faq_level = nil
        elsif faq_level
          group = group_for(heading[2])
        end
        next
      end
      next unless faq_level && (question = line.match(QUESTION))

      answer = lines[(idx + 1)..].take_while { |l| l.strip.present? && !l.match?(QUESTION) && !l.start_with?("#") }
      next if answer.empty?

      items << { faq_group: group, question: question[1].strip.sub(/\AQ:\s*/i, ""), answer: answer.join(" ").squish.sub(/\AA:\s*/, "") }
    end
    items
  end

  private

  def import_item(guide_key, item, refresh, counts, errors)
    entry = FaqEntry.find_by(guide_key: guide_key, question: item[:question])
    if entry.nil?
      entry = FaqEntry.new(item.merge(guide_key: guide_key, status: "published", published_at: Time.current,
                                      last_verified_at: @verified_at))
      outcome = :created
    elsif refresh && entry.updated_by_id.nil? && (entry.answer != item[:answer] || entry.faq_group != item[:faq_group])
      entry.assign_attributes(answer: item[:answer], faq_group: item[:faq_group])
      outcome = :updated
    else
      counts[:skipped] += 1
      return
    end
    entry.save ? counts[outcome] += 1 : errors << "#{guide_key}: #{item[:question]} — #{entry.errors.full_messages.to_sentence}"
  end

  # Archives never-edited published entries whose question was removed or reworded in the guide.
  def archive_removed(guide_key, items, counts)
    questions = items.to_set { |item| item[:question] }
    FaqEntry.published.where(guide_key: guide_key, updated_by_id: nil).find_each do |entry|
      next if questions.include?(entry.question)

      counts[:archived] += 1 if entry.update(status: "archived")
    end
  end

  # @param heading [String]
  # @return [String] a FaqEntry::GROUPS key
  def group_for(heading)
    GROUP_RULES.find { |pattern, _| heading.match?(pattern) }&.last || "troubleshooting"
  end
end
