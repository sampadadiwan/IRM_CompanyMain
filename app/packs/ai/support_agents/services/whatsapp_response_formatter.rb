# frozen_string_literal: true

# Converts HTML/Markdown agent responses into WhatsApp-friendly plain text.
#
# WhatsApp supports a limited subset of formatting:
#   *bold* for bold text
#   _italic_ for italic text
#   ~strikethrough~
#   ```code```
#
# All HTML tags, Markdown tables, and chart rendering blocks are stripped or
# converted. Message length is capped at 4096 characters (WATI session message limit).
#
class WhatsappResponseFormatter
  WATI_MAX_LENGTH = 4096

  # @param text [String] raw HTML or Markdown from the LLM
  # @return [String] WhatsApp-compatible plain text
  def self.format(text)
    new(text).format
  end

  def initialize(text)
    @text = text.to_s
  end

  def format
    result = @text.dup

    result = strip_chart_blocks(result)
    result = convert_html_tables(result)
    result = strip_html_tags(result)
    result = convert_markdown_tables(result)
    result = convert_markdown_links(result)
    result = convert_bold(result)
    result = convert_headers(result)
    result = normalize_whitespace(result)
    truncate(result)
  end

  private

  # Remove chart rendering divs — not renderable on WhatsApp
  def strip_chart_blocks(text)
    text
      .gsub(%r{<div[^>]*data-controller="chart-renderer"[^>]*>.*?</div>}m, "📊 Chart available on the web portal")
      .gsub(%r{<canvas[^>]*data-chart-renderer-target[^>]*>.*?</canvas>}m, "")
  end

  # Convert simple HTML tables to a pipe-separated text layout
  def convert_html_tables(text)
    text.gsub(%r{<table[^>]*>(.*?)</table>}mi) do |_table_match|
      table_content = ::Regexp.last_match(1)
      rows = table_content.scan(%r{<tr[^>]*>(.*?)</tr>}mi).map(&:first)
      rows.map do |row|
        cells = row.scan(%r{<t[dh][^>]*>(.*?)</t[dh]>}mi).map { |c| strip_html_tags(c.first).strip }
        cells.join(" | ")
      end.join("\n")
    end
  end

  # Strip all remaining HTML tags
  def strip_html_tags(text)
    text
      .gsub(%r{<br\s*/?>}, "\n")
      .gsub(%r{</?(p|div|section|article|header|footer|main|li|ul|ol)[^>]*>}, "\n")
      .gsub(/<[^>]+>/, "")
      .gsub('&amp;', "&")
      .gsub('&lt;', "<")
      .gsub('&gt;', ">")
      .gsub('&nbsp;', " ")
      .gsub('&quot;', '"')
      .gsub('&#39;', "'")
  end

  # Convert Markdown pipe tables to aligned text
  def convert_markdown_tables(text)
    text.gsub(/(\|.+\|\n)((?:\|[-: ]+\|\n))((?:\|.+\|\n?)+)/) do
      header_row = ::Regexp.last_match(1)
      body_rows = ::Regexp.last_match(3)

      rows = ([header_row] + body_rows.split("\n")).map do |row|
        row.split("|").map(&:strip).reject(&:empty?)
      end
      rows.map { |r| r.join(" | ") }.join("\n")
    end
  end

  # Convert [text](url) Markdown links to "text: url"
  def convert_markdown_links(text)
    text.gsub(/\[([^\]]+)\]\(([^)]+)\)/, '\1: \2')
  end

  # Convert **bold** and __bold__ to *bold* (WhatsApp bold)
  def convert_bold(text)
    text
      .gsub(/\*\*(.+?)\*\*/, '*\1*')
      .gsub(/__(.+?)__/, '*\1*')
  end

  # Convert Markdown headers (## Heading) to *Heading* (WhatsApp bold line)
  def convert_headers(text)
    text.gsub(/^\#{1,6}\s+(.+)$/) { "*#{::Regexp.last_match(1)}*" }
  end

  # Collapse excessive blank lines but preserve paragraph breaks
  def normalize_whitespace(text)
    text
      .gsub(/[ \t]+/, " ")
      .gsub(/\n{3,}/, "\n\n")
      .strip
  end

  def truncate(text)
    return text if text.length <= WATI_MAX_LENGTH

    "#{text[0, WATI_MAX_LENGTH - 3]}..."
  end
end
