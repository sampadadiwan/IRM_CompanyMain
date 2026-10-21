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

  parameter :keywords,
            type: :string,
            description: 'Space-separated search keywords (e.g. "capital call create")',
            required: true

  GUIDES_DIR = Rails.root.join("docs/user_guides").freeze
  MAX_RESULTS = 10
  # A single guide may not crowd out every other guide from the result list.
  MAX_RESULTS_PER_FILE = 3
  CONTEXT_LINES = 5

  # UI vocabulary vs guide vocabulary. The screens call an Investor a "Stakeholder", so a
  # keyword in either vocabulary must also match the other, both in passages and in filenames.
  # The other rows cover words users type that the guides spell differently: industry jargon
  # ("drawdown", "LP") and spelling variants
  # ("2FA", "esign"). Values are matched as stems, so a multi-word value such as "form type"
  # still finds "Form Types".
  SYNONYMS = {
    "stakeholder" => %w[investor],
    "stakeholders" => %w[investors],
    "investor" => %w[stakeholder],
    "investors" => %w[stakeholders],
    "lp" => ["investor", "stakeholder", "limited partner"],
    "lps" => ["investors", "stakeholders", "limited partners"],
    "drawdown" => ["capital call"],
    "drawdowns" => ["capital calls"],
    "payout" => %w[distribution],
    "payouts" => %w[distributions],
    "folio" => %w[commitment],
    "folios" => %w[commitments],
    # LP vocabulary: a "contribution" (or "subscription") agreement or template is the commitment
    # agreement / Commitment Template.
    "contribution" => %w[commitment],
    "contributions" => %w[commitments],
    "subscription" => %w[commitment],
    "subscriptions" => %w[commitments],
    "docgen" => ["generate documents", "document template"],
    # Same record, two names: the screens say "Stakeholder User", the model is InvestorAccess.
    # Multi-word keys only take effect in Elasticsearch (the database fallback splits on words).
    "investor access" => ["stakeholder user"],
    "stakeholder user" => ["investor access"],
    "investor accesses" => ["stakeholder users"],
    "stakeholder users" => ["investor accesses"],
    # Custom notifications are what users call email or notification templates.
    "email template" => ["custom notification"],
    "notification template" => ["custom notification"],
    "email templates" => ["custom notifications"],
    "adhock" => %w[adhoc],
    # E-sign signers: users say "signer"/"trustee"; templates use signatory labels.
    "signer" => %w[signatory],
    "signers" => %w[signatories],
    "trustee" => ["signatory", "other signer"],
    "esign" => %w[e-sign e-signature signature signatory],
    "2fa" => ["two-factor", "two factor", "two_factor"],
    "mfa" => ["two-factor", "two factor", "multi-factor"],
    "otp" => %w[two-factor authenticator],
    "esignature" => %w[e-signature signature],
    "esignatures" => %w[e-signatures signatures],
    "login" => ["sign in", "sign-in", "access"],
    "wire" => %w[remittance payment],
    "wires" => %w[remittances payments],
    "employee" => %w[user],
    "employees" => %w[users],
    "navigate" => ["where to find it", "sidebar", "menu"],
    "find" => ["where to find it", "sidebar", "menu"],
    "where" => ["where to find it", "sidebar", "menu"]
  }.freeze

  # Filler words stripped from the question; kept here for the step definitions that reference it.
  STOP_WORDS = GuideSearch::STOP_WORDS

  # Lines that rank like headings even though they do not start with "#": the bold-only
  # question line of an FAQ entry ("**How do I create a capital call?**") and the
  # "> **Where to find it:**" navigation box under every guide intro. Both are the lines a
  # "how to" question is most likely to be answered by, so they get the heading boost.
  HEADING_LIKE = /\A\s*(#|\*\*[^*]+\*\*\s*\z|>\s*\*\*Where to find it)/i

  # @param keywords [String] space-separated search terms
  # @return [String] matching FAQ entries and guide passages, or a no-results message
  def execute(keywords:)
    Rails.logger.info "[SearchUserGuidesTool] Called with keywords: #{keywords}"

    terms = search_terms(keywords)
    return "Please provide at least one search keyword." if terms.empty?

    faq = GuideSearch.new.call(keywords)
    matches = search_files(terms, limit: MAX_RESULTS - faq.hits.size)
    record_search(terms, faq, matches)

    Rails.logger.info "[SearchUserGuidesTool] #{faq.hits.size} FAQ (#{faq.backend}) + #{matches.size} passages for: #{terms.join(', ')}"
    matches.each { |m| Rails.logger.info "[SearchUserGuidesTool]   -> #{m[:file]}:#{m[:line]}" }

    if faq.hits.empty? && matches.empty?
      return "No matching guides found for: #{keywords}. Consider rephrasing or asking " \
             "the user to clarify their question."
    end

    [format_faq_hits(faq.hits), (format_matches(matches, terms) if matches.any?)].compact_blank.join("\n")
  end

  # @return [Boolean] whether any search this turn found a FAQ entry or passage
  def guide_search_hit?
    @guide_search_hit || false
  end

  # @return [Boolean] whether this tool was called at least once
  def searched?
    @searched_terms.present?
  end

  # @return [Hash] attributes for the assistant AgentChatMessage of this turn
  def message_attributes
    {
      guide_search_hit: guide_search_hit?,
      guide_search_strong_hit: @guide_search_strong_hit || false,
      guide_search_terms: @searched_terms.uniq.join(" ").truncate(255, omission: ""),
      tool_calls_summary: { "guide_search" => @search_log }
    }
  end

  # @return [Array<Hash>] files and passages from the last search, for tool_calls_summary
  def last_search_results
    @last_search_results || []
  end

  private

  # @param keywords [String]
  # @return [Array<String>] distinct keywords with punctuation and filler words removed
  #   (falls back to the filler words if nothing else was given)
  def search_terms(keywords)
    GuideSearch.terms(keywords)
  end

  # Accumulates across calls in one turn: the agent may search several times before answering.
  def record_search(terms, faq, matches)
    strong_passage = matches.any? { |m| m[:heading] && m[:term_hits] >= (terms.size * GuideSearch::STRONG_MATCH_RATIO).ceil }
    @searched_terms = (@searched_terms || []) + terms
    @guide_search_hit ||= faq.hits.any? || matches.any?
    @guide_search_strong_hit ||= faq.strong? || strong_passage
    (@search_log ||= []) << {
      "terms" => terms, "backend" => faq.backend.to_s,
      "faq" => faq.hits.map { |h| { "id" => h.entry_id, "score" => h.score.round(3), "strong" => h.strong } },
      "passages" => matches.map { |m| "#{m[:file]}:#{m[:line]}" }
    }
  end

  # @param hits [Array<GuideSearch::Hit>]
  # @return [String]
  def format_faq_hits(hits)
    return "" if hits.empty?

    lines = ["Found #{hits.size} FAQ entr#{hits.size == 1 ? 'y' : 'ies'}. Quote the answer and link its URL when it answers the question.\n"]
    hits.each_with_index do |hit, idx|
      lines << "--- FAQ #{idx + 1}: #{hit.guide_title} (#{hit.url}) ---"
      lines << "Q: #{hit.question}"
      lines << "A: #{hit.answer}"
      lines << ""
    end
    lines.join("\n")
  end

  # Guides whose FAQs live in FAQ Manager: their Markdown FAQ sections are skipped by the
  # passage search so the chatbot never quotes a stale copy of an answer.
  #
  # @return [Set<String>] guide keys
  def database_faq_guides
    @database_faq_guides ||= FaqEntry.published.distinct.pluck(:guide_key).to_set
  end

  # Ranks passages by how many distinct keywords they contain (a passage matching every
  # keyword beats one matching a single common word like "create"), then by keywords in the
  # guide's filename, then headings (and the heading-like FAQ question and "Where to find it"
  # lines, see HEADING_LIKE) before body text, then by keywords on the matched line, then by
  # keywords on the matched line spelled as typed rather than as a synonym (so for "create
  # stakeholder", "Creating a Stakeholder" beats "a KYC the investor created" instead of the
  # tie falling to the alphabetical filename order).
  #
  # @param terms [Array<String>] search keywords
  # @param limit [Integer] maximum passages to return
  # @return [Array<Hash>] matched file/line/snippet triples
  def search_files(terms, limit: MAX_RESULTS)
    term_patterns = terms.map { |t| term_pattern(t) }
    # The keyword itself, in any inflection, without its synonyms
    literal_patterns = terms.map { |t| GuideSearch.term_pattern(t, {}) }
    any_term = Regexp.union(term_patterns)
    results = []

    Dir.glob(GUIDES_DIR.join("**/*.md")).each do |file_path|
      relative_path = Pathname.new(file_path).relative_path_from(Rails.root).to_s
      # Underscores become spaces so a multi-word synonym ("capital call") matches
      # "capital_calls_user_guide" the same way it matches the prose.
      filename = File.basename(file_path, ".md").tr("_", " ")
      filename_hits = term_patterns.count { |p| filename.match?(p) }

      lines = File.readlines(file_path)
      skip_faq = database_faq_guides.include?(relative_path.delete_prefix("docs/user_guides/").delete_suffix(".md"))
      faq_level = nil
      last_matched_line = -100
      lines.each_with_index do |line, idx|
        faq_level = faq_section_level(line, faq_level) if skip_faq
        next if faq_level
        next unless line.match?(any_term)
        next if idx - last_matched_line <= CONTEXT_LINES * 2

        snippet = extract_context(lines, idx)
        results << {
          file: relative_path,
          line: idx + 1,
          snippet: snippet,
          filename_hits: filename_hits,
          term_hits: term_patterns.count { |p| snippet.match?(p) },
          line_hits: term_patterns.count { |p| line.match?(p) },
          literal_line_hits: literal_patterns.count { |p| line.match?(p) },
          heading: line.match?(HEADING_LIKE)
        }
        last_matched_line = idx
      end
    end

    ranked = results.sort_by do |r|
      [-r[:term_hits], -r[:filename_hits], r[:heading] ? 0 : 1, -r[:line_hits], -r[:literal_line_hits], r[:file], r[:line]]
    end
    per_file = Hash.new(0)
    ranked.select { |r| (per_file[r[:file]] += 1) <= MAX_RESULTS_PER_FILE }
          .first([limit, 0].max)
          .tap { |r| @last_search_results = r }
  end

  # @param line [String]
  # @param current [Integer, nil] level of the FAQ heading we are inside, if any
  # @return [Integer, nil] the FAQ heading level while inside an FAQ section, nil outside
  def faq_section_level(line, current)
    heading = line.match(/\A(#+)\s+(.*)/)
    return current unless heading
    return heading[1].size if heading[2].strip.match?(WithGuideRendering::FAQ_HEADING)
    return nil if current && heading[1].size <= current

    current
  end

  # @param term [String] one keyword
  # @return [Regexp] matches the keyword or any of its synonyms, case-insensitively, in any
  #   inflection ("create" also matches "Creating"/"created"; "calls" also matches "call")
  #   Synonyms are the built-in SYNONYMS plus the ops-managed GuideSearchSynonym rules.
  def term_pattern(term)
    @expansions ||= GuideSearchSynonym.expansions
    GuideSearch.term_pattern(term, @expansions)
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
