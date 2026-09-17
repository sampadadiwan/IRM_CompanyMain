# frozen_string_literal: true

# Matches a stakeholder string from an email against a deal's DealInvestors.
#
# Implements Tier A matching only (MVP): high-confidence match against
# deal-attached stakeholders. Never searches globally.
#
# Normalization (applied to both sides):
#   - Lowercase, strip punctuation, collapse whitespace
#   - Strip diacritics ("Söderberg" → "Soderberg")
#   - Strip entity suffixes: Ltd, LLC, Inc, LP, GmbH, PLC, Capital,
#     Partners, Ventures, VC, Fund, Group, Holdings
#
# Match rules:
#   - Exact normalized match, single candidate → auto-file (Tier A)
#   - Single fuzzy match ≥ 0.85 → auto-file (Tier A)
#   - Everything else → warehouse
#
# @see DealIngestProcessor for the orchestrator that calls this
# @see DealEmailParser for the LLM parser that provides the stakeholder_string
class DealStakeholderMatcher
  # Entity suffixes to strip during normalization.
  ENTITY_SUFFIXES = %w[
    ltd llc inc lp gmbh plc sa nv bv ag
    capital partners ventures vc fund group holdings
    management advisors advisory investments
  ].freeze

  # Minimum fuzzy score to auto-file (Tier A).
  FUZZY_THRESHOLD = 0.85

  # Result of a match attempt.
  #
  # @attr matched [Boolean] whether a confident match was found
  # @attr deal_investor [DealInvestor, nil] the matched investor (if matched)
  # @attr confidence [Float] match confidence score (0.0–1.0)
  # @attr candidates [Array<Hash>] all candidates considered with scores
  Result = Struct.new(:matched, :deal_investor, :confidence, :candidates, keyword_init: true)

  # Match a stakeholder string against a deal's investors.
  #
  # @param stakeholder_string [String] the name from the LLM parser
  # @param deal [Deal] the deal to search within
  # @return [Result]
  def self.call(stakeholder_string:, deal:)
    new(stakeholder_string:, deal:).match
  end

  def initialize(stakeholder_string:, deal:)
    @stakeholder_string = stakeholder_string
    @deal = deal
  end

  # Run the matching algorithm.
  #
  # @return [Result]
  def match
    return no_match if @stakeholder_string.blank?

    normalized_query = normalize(@stakeholder_string)
    return no_match if normalized_query.blank?

    candidates = score_candidates(normalized_query)
    return no_match if candidates.empty?

    best = candidates.max_by { |c| c[:score] }

    if best[:score] >= FUZZY_THRESHOLD && single_top_match?(candidates)
      Result.new(
        matched: true,
        deal_investor: best[:deal_investor],
        confidence: best[:score],
        candidates: candidates
      )
    else
      Result.new(
        matched: false,
        deal_investor: nil,
        confidence: best[:score],
        candidates: candidates
      )
    end
  end

  private

  # Score each deal investor against the query string.
  #
  # @param normalized_query [String] normalized stakeholder string
  # @return [Array<Hash>] candidates with :deal_investor, :name, :score
  def score_candidates(normalized_query)
    @deal.deal_investors.includes(:investor).map do |di|
      name = di.investor.investor_name
      normalized_name = normalize(name)
      score = similarity(normalized_query, normalized_name)

      { deal_investor: di, name: name, score: score }
    end
  end

  # Check that only one candidate exceeds the fuzzy threshold.
  # If two or more candidates are above threshold, we can't confidently pick one → warehouse.
  #
  # @param candidates [Array<Hash>] scored candidates
  # @return [Boolean]
  def single_top_match?(candidates)
    candidates.one? { |c| c[:score] >= FUZZY_THRESHOLD }
  end

  # Normalize a name for comparison.
  # Lowercase, strip diacritics, remove punctuation, strip entity suffixes,
  # collapse whitespace.
  #
  # @param text [String] raw name
  # @return [String] normalized name
  def normalize(text)
    result = text.dup
    result = result.downcase
    result = strip_diacritics(result)
    result = result.gsub(/[^a-z0-9\s]/, "")
    result = strip_suffixes(result)
    result.squish
  end

  # Remove diacritics by decomposing Unicode and stripping combining marks.
  # "Söderberg" → "Soderberg", "Café" → "Cafe"
  #
  # @param text [String]
  # @return [String]
  def strip_diacritics(text)
    text.unicode_normalize(:nfd).gsub(/\p{Mn}/, "")
  end

  # Remove common entity suffixes from the end of a name.
  #
  # @param text [String] lowercased, punctuation-stripped name
  # @return [String]
  def strip_suffixes(text)
    words = text.split
    words.pop while words.any? && ENTITY_SUFFIXES.include?(words.last)
    words.join(" ")
  end

  # Dice coefficient — measures similarity between two strings using bigrams.
  # Returns 1.0 for identical strings, 0.0 for completely different ones.
  # Chosen because it handles substring matches well (e.g. "Sequoia" vs
  # "Sequoia Capital") and doesn't need an external gem.
  #
  # @param a [String] first string
  # @param b [String] second string
  # @return [Float] similarity score 0.0–1.0
  def similarity(a, b)
    return 1.0 if a == b
    return 0.0 if a.empty? || b.empty?

    bigrams_a = bigrams(a)
    bigrams_b = bigrams(b)

    return 0.0 if bigrams_a.empty? || bigrams_b.empty?

    intersection = (bigrams_a & bigrams_b).size
    (2.0 * intersection) / (bigrams_a.size + bigrams_b.size)
  end

  # Generate bigrams (character pairs) from a string.
  #
  # @param str [String]
  # @return [Array<String>]
  def bigrams(str)
    (0...(str.length - 1)).map { |i| str[i, 2] }
  end

  # Return a no-match result with empty candidates.
  #
  # @return [Result]
  def no_match
    Result.new(matched: false, deal_investor: nil, confidence: 0.0, candidates: [])
  end
end
