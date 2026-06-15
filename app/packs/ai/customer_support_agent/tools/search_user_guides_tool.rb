# frozen_string_literal: true

# Keyword search over FM-facing user guides stored as Markdown files in docs/user_guides/.
# Returns matching passages with file paths and line numbers. Records hit/miss on the
# message for guide gap tracking (Module 8).
#
# @see FmCsChatProvider
class SearchUserGuidesTool < RubyLLM::Tool
  description "Search the platform user guides for information about how to use CapHive features. " \
              "Pass one or more keywords. Returns matching passages from the guides with file names. " \
              "Use this tool FIRST before attempting a SQL query when the user asks a 'how to' question."

  param :keywords,
        type: :string,
        desc: 'Space-separated search keywords (e.g. "capital call create")',
        required: true

  GUIDES_DIR = Rails.root.join("docs/user_guides").freeze
  MAX_RESULTS = 10
  CONTEXT_LINES = 5

  # @param keywords [String] space-separated search terms
  # @return [String] matched passages or a no-results message
  def execute(keywords:)
    Rails.logger.info "[SearchUserGuidesTool] Called with keywords: #{keywords}"

    terms = keywords.to_s.strip.split(/\s+/).compact_blank
    return "Please provide at least one search keyword." if terms.empty?

    pattern = Regexp.new(terms.map { |t| Regexp.escape(t) }.join("|"), Regexp::IGNORECASE)
    matches = search_files(pattern, terms)

    Rails.logger.info "[SearchUserGuidesTool] Found #{matches.size} matches for: #{terms.join(', ')}"
    matches.each { |m| Rails.logger.info "[SearchUserGuidesTool]   -> #{m[:file]}:#{m[:line]}" }

    if matches.empty?
      @guide_search_hit = false
      return "No matching guides found for: #{keywords}. Consider rephrasing or asking " \
             "the user to clarify their question."
    end

    @guide_search_hit = true
    format_matches(matches, terms)
  end

  # @return [Boolean] whether the last search found any matches
  def guide_search_hit?
    @guide_search_hit || false
  end

  # @return [Array<Hash>] files and passages from the last search, for tool_calls_summary
  def last_search_results
    @last_search_results || []
  end

  private

  # @param pattern [Regexp]
  # @return [Array<Hash>] matched file/line/snippet triples
  def search_files(pattern, terms)
    results = []

    Dir.glob(GUIDES_DIR.join("**/*.md")).sort.each do |file_path|
      relative_path = Pathname.new(file_path).relative_path_from(Rails.root).to_s
      filename = File.basename(file_path, ".md").downcase
      filename_hits = terms.count { |t| filename.include?(t.downcase) }

      lines = File.readlines(file_path)
      last_matched_line = -100
      lines.each_with_index do |line, idx|
        next unless line.match?(pattern)
        next if idx - last_matched_line <= CONTEXT_LINES * 2

        snippet = extract_context(lines, idx)
        results << { file: relative_path, line: idx + 1, snippet: snippet, filename_hits: filename_hits }
        last_matched_line = idx
      end
    end

    results.sort_by { |r| [-r[:filename_hits], r[:file], r[:line]] }
           .first(MAX_RESULTS)
           .tap { |r| @last_search_results = r }
  end

  # @param lines [Array<String>] all lines in the file
  # @param match_idx [Integer] zero-based index of the matching line
  # @return [String] the matching line plus surrounding context
  def extract_context(lines, match_idx)
    start_idx = [match_idx - CONTEXT_LINES, 0].max
    end_idx = [match_idx + CONTEXT_LINES, lines.size - 1].min
    lines[start_idx..end_idx].map(&:rstrip).join("\n")
  end

  # @param matches [Array<Hash>]
  # @param terms [Array<String>]
  # @return [String] formatted results for the LLM
  def format_matches(matches, terms)
    lines = ["Found #{matches.size} matching passage(s) for: #{terms.join(', ')}\n"]

    matches.each_with_index do |match, idx|
      lines << "--- Result #{idx + 1}: #{match[:file]} (line #{match[:line]}) ---"
      lines << match[:snippet]
      lines << ""
    end

    lines.join("\n")
  end
end
