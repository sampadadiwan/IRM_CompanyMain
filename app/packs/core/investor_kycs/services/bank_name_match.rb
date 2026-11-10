# frozen_string_literal: true

# ⑤ The bank check's name rule for KYCs (OWASP review 2026-11 M14, openspec/changes/archive/2026-11-10-bank-detail-change-controls,
# design card ⑤, D10; spec "Bank check name rule").
#
# The penny drop returns the name the bank holds for the account. Today any one shared word passed it, so "R KUMAR"
# passed for "A Kumar". Now:
#   1. the provider's own name match (fuzzy_match_result) → :match (H12);
#   2. else both names are normalised — lower case, titles dropped (Mr, Mrs, Shri, M/S …), punctuation removed,
#      company suffixes spelt one way (Private → pvt, Limited → ltd) — and it is a :match when every word of one name
#      matches a word of the other (a one-letter initial matches a word starting with it), at least one full word is
#      shared, and the shorter name has 2+ words unless both have 1 (H13, H14, E49, E50, E52);
#   3. anything else is :review — a person decides; nothing is rejected (E47, E48, E51).
#
# Pure string work; never raises. KYCs only — secondary-sale offers and interests keep VerifyBankJob's old rule (E55).
class BankNameMatch
  TITLES = %w[mr mrs ms miss dr shri smt sri m/s kum master].freeze
  SUFFIXES = { "private" => "pvt", "limited" => "ltd" }.freeze

  def self.call(kyc_name:, bank_name:, provider_match:)
    new(kyc_name, bank_name, provider_match).call
  end

  def initialize(kyc_name, bank_name, provider_match)
    @kyc_words = words(kyc_name)
    @bank_words = words(bank_name)
    @provider_match = provider_match
  end

  def call
    # H12 — the provider matched the names itself
    return :match if @provider_match
    # Nothing to compare: a person looks at it
    return :review if @kyc_words.empty? || @bank_words.empty?

    covered? ? :match : :review
  end

  private

  # E47, E48, E50, E52 — one side's every word is in the other (either direction), with a full word in common, and
  # a one-word name only against a one-word name ("KUMAR" alone is not "A Kumar")
  def covered?
    shorter, longer = [@kyc_words, @bank_words].sort_by(&:size)
    return false if shorter.size == 1 && longer.size > 1
    return false unless full_word_shared?

    all_in?(@bank_words, @kyc_words) || all_in?(@kyc_words, @bank_words)
  end

  def all_in?(these, those)
    these.all? { |word| those.any? { |other| same_word?(word, other) } }
  end

  # "a" matches "anil" (an initial), "kumar" matches "kumar"
  def same_word?(one, other)
    one == other || (one.size == 1 && other.start_with?(one)) || (other.size == 1 && one.start_with?(other))
  end

  def full_word_shared?
    @kyc_words.reject { |w| w.size == 1 }.intersect?(@bank_words.reject { |w| w.size == 1 })
  end

  # "Mr. A. Kumar" → ["a", "kumar"]; "ABC Private Limited" → ["abc", "pvt", "ltd"]
  def words(name)
    name.to_s.downcase.split(/[\s,]+/).filter_map do |raw|
      next if TITLES.include?(raw.delete("."))

      word = raw.gsub(/[^a-z0-9]/, "")
      next if word.empty? || TITLES.include?(word)

      SUFFIXES.fetch(word, word)
    end
  end
end
