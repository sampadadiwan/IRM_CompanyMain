# frozen_string_literal: true

# Searches published FAQ entries for the Customer Support Agent (SearchUserGuidesTool).
#
# Uses Elasticsearch (FaqEntryIndex) and falls back to a database search when Elasticsearch is
# unavailable, errors, or in the test environment (where Chewy is bypassed). Both backends
# apply the same synonyms and the same strong-match rule.
#
# A result is a **strong** match when it matches at least STRONG_MATCH_RATIO of the search
# terms in its question, keywords or guide title. A search with no strong result counts as a
# chatbot miss (GuideSearchMissesController). Raw relevance scores are not used as the
# threshold because they are not comparable across queries of different lengths.
#
# @example
#   result = GuideSearch.new.call("where do I record a payment")
#   result.hits.first.question #=> "How do I record a payment from an investor?"
#   result.strong?             #=> true
class GuideSearch
  STRONG_MATCH_RATIO = 2.0 / 3
  MAX_RESULTS = 5

  # Filler words passed through from the question. They match every entry and would otherwise
  # outvote the real keywords. "where" is deliberately kept: it carries navigation intent.
  STOP_WORDS = %w[a an and are can do does for how i in is it my of on or the to what with].freeze

  Hit = Data.define(:entry_id, :guide_key, :guide_title, :faq_group, :question, :answer, :score, :strong) do
    # @return [String] in-app URL of the entry on its guide page
    def url
      "/user_guides/#{guide_key}#faq-#{entry_id}"
    end
  end

  Result = Data.define(:hits, :backend, :terms) do
    # @return [Boolean] whether any hit matched at least STRONG_MATCH_RATIO of the terms
    def strong?
      hits.any?(&:strong)
    end
  end

  # @param keywords [String]
  # @return [Array<String>] distinct lowercase terms without filler words
  def self.terms(keywords)
    words = keywords.to_s.downcase.scan(/[[:alnum:]_-]+/).uniq
    words.reject { |w| STOP_WORDS.include?(w) }.presence || words
  end

  # Light stemmer: strips a common English suffix when what remains is still a usable prefix.
  #
  # @param word [String]
  # @return [String]
  def self.stem(word)
    stemmed = word.downcase.sub(/(ing|ed|es|s|e)\z/, "")
    stemmed.length >= 4 ? stemmed : word.downcase
  end

  # @param term [String]
  # @param expansions [Hash{String => Array<String>}] from GuideSearchSynonym.expansions
  # @return [Regexp] matches the term or any synonym, case-insensitively, in any inflection
  def self.term_pattern(term, expansions = GuideSearchSynonym.expansions)
    words = [term, *expansions.fetch(term.downcase, [])]
    Regexp.new(words.map { |w| Regexp.escape(stem(w)) }.join("|"), Regexp::IGNORECASE)
  end

  # @param audience [String] "signed_in" (sees signed_in and public entries) or "public"
  def initialize(audience: "signed_in")
    @audiences = audience.to_s == "public" ? %w[public] : FaqEntry::AUDIENCES
  end

  # @param keywords [String]
  # @return [Result]
  def call(keywords)
    terms = self.class.terms(keywords)
    return Result.new(hits: [], backend: :none, terms: terms) if terms.empty?

    if elasticsearch?
      begin
        return Result.new(hits: elasticsearch_hits(keywords), backend: :elasticsearch, terms: terms)
      rescue StandardError => e
        Rails.logger.warn("[GuideSearch] Elasticsearch failed, using database fallback: #{e.class}: #{e.message}")
      end
    end
    Result.new(hits: database_hits(terms), backend: :database, terms: terms)
  end

  private

  def elasticsearch?
    !Rails.env.test? && ENV["GUIDE_SEARCH_BACKEND"] != "database"
  end

  # @param keywords [String]
  # @return [Array<Hit>]
  def elasticsearch_hits(keywords)
    response = Chewy.client.search(index: FaqEntryIndex.index_name, body: elasticsearch_query(keywords), timeout: "1500ms")
    response.dig("hits", "hits").map do |hit|
      source = hit["_source"]
      Hit.new(entry_id: hit["_id"].to_i, guide_key: source["guide_key"], guide_title: source["guide_title"],
              faq_group: source["faq_group"], question: source["question"], answer: source["answer"],
              score: hit["_score"].to_f, strong: Array(hit["matched_queries"]).include?("strong"))
    end
  end

  # The named "strong" clause has boost 0: it never changes ranking, it only reports (through
  # matched_queries) whether a hit matched two-thirds of the terms in its question-like fields.
  #
  # @param keywords [String]
  # @return [Hash]
  def elasticsearch_query(keywords)
    {
      size: MAX_RESULTS,
      query: {
        bool: {
          must: { multi_match: { query: keywords, type: "best_fields", tie_breaker: 0.3,
                                 fields: %w[question^4 keywords^3 guide_title^2 answer] } },
          should: [{ multi_match: { query: keywords, type: "cross_fields", fields: %w[question keywords guide_title],
                                    minimum_should_match: "67%", boost: 0, _name: "strong" } }],
          filter: [{ terms: { audience: @audiences } }]
        }
      }
    }
  end

  # @param terms [Array<String>]
  # @return [Array<Hit>]
  def database_hits(terms)
    expansions = GuideSearchSynonym.expansions
    patterns = terms.index_with { |t| self.class.term_pattern(t, expansions) }
    candidates(terms, expansions).filter_map do |entry|
      title = GuideCatalog.title(entry.guide_key)
      heading_hits = patterns.values.count { |p| [entry.question, entry.keywords, title].any? { |text| text.to_s.match?(p) } }
      answer_hits = patterns.values.count { |p| entry.answer.to_s.match?(p) }
      next if heading_hits.zero? && answer_hits.zero?

      Hit.new(entry_id: entry.id, guide_key: entry.guide_key, guide_title: title, faq_group: entry.faq_group,
              question: entry.question, answer: entry.answer, score: (heading_hits * 3) + answer_hits,
              strong: heading_hits >= (terms.size * STRONG_MATCH_RATIO).ceil)
    end.sort_by { |hit| [-hit.score, hit.guide_key, hit.entry_id] }.first(MAX_RESULTS)
  end

  # Narrows to entries containing any term or synonym stem, so only matching rows are loaded.
  #
  # @return [ActiveRecord::Relation<FaqEntry>]
  def candidates(terms, expansions)
    stems = terms.flat_map { |t| [t, *expansions.fetch(t, [])] }.map { |w| self.class.stem(w) }.uniq
    table = FaqEntry.arel_table
    condition = stems.map do |s|
      like = "%#{FaqEntry.sanitize_sql_like(s)}%"
      table[:question].matches(like).or(table[:keywords].matches(like)).or(table[:answer].matches(like))
    end.reduce(:or)
    FaqEntry.published.where(audience: @audiences).where(condition)
            .select(:id, :guide_key, :faq_group, :question, :keywords, :answer).limit(500)
  end
end
