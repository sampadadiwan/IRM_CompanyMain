# frozen_string_literal: true

# Every FAQ across the user guides, for the all-FAQs index page (FaqsController).
#
# Uses the same source a guide page does: a guide's published FaqEntry rows once it has any,
# otherwise the FAQ section written in its Markdown file. Answers are rendered to HTML with
# links rewritten to work from /faqs (in-guide anchors and relative guide links would
# otherwise resolve against the index page).
class FaqCatalog
  Item = Data.define(:group_label, :question, :answer_html)
  Guide = Data.define(:key, :title, :items) do
    # @return [String] in-app URL of the guide
    def url
      "/user_guides/#{key}"
    end
  end

  # @param audience [String] "signed_in" or "public"
  def initialize(audience: "signed_in")
    @audience = audience
  end

  # @return [Array<Guide>] guides that have at least one FAQ, ordered by title
  def guides
    Rails.cache.fetch(cache_key) { build }
  end

  private

  def build
    GuideCatalog.guide_keys.filter_map do |key|
      items = database_items(key).presence || markdown_items(key)
      Guide.new(key: key, title: GuideCatalog.title(key), items: items) if items.any?
    end.sort_by(&:title)
  end

  # @return [Array<Item>]
  def database_items(key)
    FaqSectionRenderer.new(key, audience: @audience).entries.map do |entry|
      Item.new(group_label: entry.group_label, question: entry.question, answer_html: answer_html(entry.answer, key))
    end
  end

  # @return [Array<Item>]
  def markdown_items(key)
    return [] if @audience == "public"

    FaqMarkdownImporter.new.parse(key).map do |item|
      Item.new(group_label: FaqEntry::GROUPS[item[:faq_group]], question: item[:question],
               answer_html: answer_html(item[:answer], key))
    end
  end

  # @param text [String] answer Markdown
  # @param key [String] guide the answer belongs to
  # @return [String] HTML with in-guide anchors and relative guide links made absolute
  def answer_html(text, key)
    fragment = Nokogiri::HTML::DocumentFragment.parse(FaqSectionRenderer.answer_html(text))
    fragment.css("a[href]").each do |link|
      href = link["href"]
      if href.start_with?("#")
        link["href"] = "/user_guides/#{key}#{href}"
      elsif !href.match?(%r{\A([a-z][a-z0-9+.-]*:|/)}i)
        target, anchor = href.split("#", 2)
        resolved = (Pathname.new(key).dirname + target.delete_suffix(".md")).cleanpath
        link["href"] = "/user_guides/#{resolved}#{"##{anchor}" if anchor}"
      end
    end
    fragment.to_html
  end

  # Changes when any guide file or any FAQ entry changes.
  def cache_key
    files = Dir.glob(GuideCatalog::ROOT.join("**", "*.md"))
    ["faq_catalog", @audience, files.size, files.map { |f| File.mtime(f).to_i }.max,
     FaqEntry.count, FaqEntry.maximum(:updated_at)&.to_i]
  end
end
