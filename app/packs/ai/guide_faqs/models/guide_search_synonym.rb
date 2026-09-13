# frozen_string_literal: true

# An ops-managed synonym rule for the Customer Support Agent's guide search, in
# Elasticsearch/Solr synonym syntax:
#
#   "drawdown, capital call"                    — equivalent terms
#   "lp => investor, stakeholder, limited partner" — one-way expansion
#
# Enabled rules are compiled into FaqEntryIndex's search analyzer (the index is rebuilt in the
# background on save, which takes seconds at FAQ scale) and applied by GuideSearch's database
# fallback. The built-in SearchUserGuidesTool::SYNONYMS always apply as well.
class GuideSearchSynonym < ApplicationRecord
  audited

  FORMAT = /\A[^=,]+(,[^=,]+)*(\s*=>\s*[^=,]+(,[^=,]+)*)?\z/

  belongs_to :updated_by, class_name: "User", optional: true

  validates :terms, presence: true, length: { maximum: 500 }, format: { with: FORMAT, message: "must look like 'a, b' or 'a => b, c'" }
  validates :note, length: { maximum: 255 }

  scope :enabled, -> { where(enabled: true) }

  after_commit -> { GuideSearchReindexJob.perform_later }

  # @return [Array<String>] every enabled rule plus the built-in synonyms, as Elasticsearch rules
  def self.rules
    built_in = SearchUserGuidesTool::SYNONYMS.map { |term, values| "#{term} => #{([term] + values).join(', ')}" }
    built_in + enabled.pluck(:terms).map { |t| normalise(t) }
  end

  # @return [Hash{String => Array<String>}] lowercase term => terms it also matches, for the DB fallback
  def self.expansions
    map = Hash.new { |h, k| h[k] = [] }
    SearchUserGuidesTool::SYNONYMS.each { |term, values| map[term].concat(values) }
    enabled.pluck(:terms).each do |rule|
      lhs, rhs = normalise(rule).split("=>").map { |side| side.split(",").map(&:strip) }
      if rhs
        lhs.each { |term| map[term].concat(rhs) }
      else
        lhs.each { |term| map[term].concat(lhs - [term]) }
      end
    end
    map.transform_values(&:uniq)
  end

  # @param rule [String]
  # @return [String] lowercased, whitespace-collapsed rule
  def self.normalise(rule)
    rule.to_s.downcase.squish.gsub(/\s*,\s*/, ", ").gsub(/\s*=>\s*/, " => ")
  end
end
