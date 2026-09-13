# frozen_string_literal: true

# Drift guard for docs/user_guides/**/*.md — the Markdown the in-app guide pages render
# (WithGuideRendering) and the Customer Support Agent searches (SearchUserGuidesTool).
#
# Guides quote navigation as URL paths in backticks (`/funds`, `/investors/new`), link to
# each other with relative ids (`(fund_units_user_guide)`, `(../support_agents_user_guide)`)
# and carry an FAQ whose entries must be "**Question?**" directly followed by the answer —
# WithGuideRendering#wrap_faq_section only turns that exact shape into the accordion, and
# SearchUserGuidesTool returns the matched line ±CONTEXT_LINES, so an answer longer than
# that is truncated before the agent sees it. Each of these facts can silently rot as
# routes, files and prose change; this class checks all of them so a Cucumber scenario
# (features/core/user_guide_lint.feature) fails instead.
#
# @example
#   UserGuideLint.new.route_errors #=> ["docs/user_guides/x.md:12: /no_such_path"]
class UserGuideLint
  GUIDES_ROOT = Rails.root.join("docs/user_guides").freeze

  # Longest answer the support agent can return whole (see SearchUserGuidesTool::CONTEXT_LINES).
  MAX_ANSWER_LINES = 5

  # The question line of an FAQ entry: bold text on a line of its own.
  FAQ_QUESTION = /\A\*\*[^*]+\*\*\s*\z/

  # @param root [Pathname] directory holding the guides
  def initialize(root: GUIDES_ROOT)
    @root = root
  end

  # @return [Array<String>] every guide, as a path relative to Rails.root
  def guide_files
    Dir.glob(@root.join("**", "*.md"))
  end

  # Guides exempt from the raw-path rule: technical references whose readers need exact paths.
  RAW_PATH_EXEMPT = %w[integration.md security_hardening_changelog.md].freeze

  # Backticked app paths in guide text outside fenced code blocks. Readers do not type URLs, so
  # a fixed path must be a link and a path with a placeholder must be described in words.
  #
  # @return [Array<String>] "file:line: path" for each raw path
  def route_errors
    each_line_of_guides.flat_map do |file, lineno, line, in_fence|
      next [] if in_fence || RAW_PATH_EXEMPT.include?(File.basename(file))

      line.scan(GuideReferenceCheck::PATH_IN_BACKTICKS).flatten.map { |path| "#{file}:#{lineno}: #{path}" }
    end
  end

  # Links whose target guide does not exist, or whose app path does not route.
  #
  # @return [Array<String>] "file:line: message" for each dangling link
  def link_errors
    each_line_of_guides.flat_map do |file, lineno, line|
      key = Pathname.new(file).relative_path_from(GuideReferenceCheck::GUIDES_DIR).to_s.delete_suffix(".md")
      GuideReferenceCheck.link_errors(line, guide_key: key).map { |message| "#{file}:#{lineno}: #{message}" }
    end
  end

  # FAQ entries that will not render as an accordion entry: a question line that is not
  # directly followed by its answer (a blank line in between yields two paragraphs).
  #
  # @return [Array<String>] "file:line: question"
  def faq_shape_errors
    faq_entries.filter_map do |entry|
      "#{entry[:file]}:#{entry[:line]}: #{entry[:question]}" if entry[:answer_lines].empty?
    end
  end

  # FAQ answers longer than the support agent's search window.
  #
  # @return [Array<String>] "file:line: N lines"
  def faq_length_errors
    faq_entries.filter_map do |entry|
      count = entry[:answer_lines].size
      "#{entry[:file]}:#{entry[:line]}: #{count} lines" if count > MAX_ANSWER_LINES
    end
  end

  # Guides that have no FAQ section at all.
  #
  # @return [Array<String>] file paths
  def guides_without_faq
    guide_files.filter_map do |path|
      rel = relative(path)
      rel unless File.foreach(path).any? { |l| faq_heading?(l) }
    end
  end

  # Guides whose intro is not followed by a "> **Where to find it:**" navigation box.
  #
  # @return [Array<String>] file paths
  def guides_without_where_to_find_it
    guide_files.filter_map do |path|
      rel = relative(path)
      rel unless File.foreach(path).any? { |l| l.match?(/\A>\s*\*\*Where to find it/i) }
    end
  end

  # Guides where the in-app renderer turns fewer FAQ entries into accordion items than the
  # Markdown contains — an entry the renderer skips shows as a plain paragraph, and a
  # heading it fails to recognise as an FAQ shows no accordion at all.
  #
  # @return [Array<String>] "file: N entries, M rendered"
  def faq_render_errors
    # Render the Markdown only: once a guide has published FaqEntry rows the in-app renderer shows those
    # instead, which would make this check depend on whatever the local database holds.
    renderer = Class.new do
      include WithGuideRendering

      def database_faq_for(_path) = nil
    end.new
    faq_counts.filter_map do |file, count|
      html = renderer.send(:render_guide_markdown, Rails.root.join(file))
      rendered = Nokogiri::HTML::DocumentFragment.parse(html).css(".faq details").size
      "#{file}: #{count} entries, #{rendered} rendered" if rendered < count
    end
  end

  # Question count per guide, for reporting.
  #
  # @return [Hash{String => Integer}] relative file => number of FAQ entries
  def faq_counts
    faq_entries.group_by { |e| e[:file] }.transform_values(&:size)
  end

  private

  # @return [String] path relative to Rails.root
  def relative(path)
    Pathname.new(path).relative_path_from(Rails.root).to_s
  end

  # @return [Enumerator<Array(String, Integer, String, Boolean)>] file, 1-based line number, line, inside a code fence
  def each_line_of_guides
    return to_enum(:each_line_of_guides) unless block_given?

    guide_files.each do |path|
      rel = relative(path)
      in_fence = false
      File.foreach(path).with_index(1) do |line, lineno|
        fence_marker = line.lstrip.start_with?("```")
        in_fence = !in_fence if fence_marker
        yield rel, lineno, line, in_fence || fence_marker
      end
    end
  end

  # @param line [String]
  # @return [Boolean]
  # Same rule the renderer uses, so a heading the linter treats as an FAQ is one that
  # actually renders as an accordion.
  def faq_heading?(line)
    m = line.match(/\A#+\s+(.*)/)
    m.present? && m[1].strip.match?(WithGuideRendering::FAQ_HEADING)
  end

  # Parses every FAQ section into entries. A section runs from its heading to the next
  # heading of equal or shallower level; an entry is a FAQ_QUESTION line plus the
  # non-blank lines that directly follow it.
  #
  # @return [Array<Hash>] :file, :line, :question, :answer_lines
  def faq_entries
    @faq_entries ||= guide_files.flat_map do |path|
      rel = relative(path)
      lines = File.readlines(path, chomp: true)
      entries = []
      section_level = nil

      lines.each_with_index do |line, idx|
        if (m = line.match(/\A(#+)\s/))
          level = m[1].size
          section_level = if faq_heading?(line)
                            level
                          elsif section_level && level <= section_level
                            nil
                          else
                            section_level
                          end
          next
        end
        next unless section_level && line.match?(FAQ_QUESTION)

        answer = lines[(idx + 1)..].take_while { |l| !l.strip.empty? && !l.match?(FAQ_QUESTION) && !l.start_with?("#") }
        entries << { file: rel, line: idx + 1, question: line.strip, answer_lines: answer }
      end
      entries
    end
  end
end
