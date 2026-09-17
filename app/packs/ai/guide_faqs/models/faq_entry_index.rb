# frozen_string_literal: true

# Elasticsearch index of published FAQ entries, searched by GuideSearch for the Customer
# Support Agent. Small (a few thousand documents), so a synonym change simply rebuilds it
# (GuideSearchReindexJob) rather than using the synonyms API.
class FaqEntryIndex < Chewy::Index
  # Settings are a block so the synonym rules are read from the database each time the index
  # is (re)created, not once at class load.
  settings do
    {
      analysis: {
        filter: {
          english_stem: { type: "stemmer", language: "english" },
          guide_synonyms: { type: "synonym_graph", lenient: true, synonyms: GuideSearchSynonym.rules }
        },
        analyzer: {
          guide_index: { type: "custom", tokenizer: "standard", filter: %w[lowercase asciifolding english_stem] },
          guide_search: { type: "custom", tokenizer: "standard", filter: %w[lowercase asciifolding guide_synonyms english_stem] }
        }
      }
    }
  end

  index_scope FaqEntry.published, delete_if: -> { !published? }

  TEXT = { type: "text", analyzer: "guide_index", search_analyzer: "guide_search" }.freeze

  field :guide_key, type: "keyword"
  field :faq_group, type: "keyword"
  field :audience, type: "keyword"
  field :guide_title, **TEXT, value: -> { guide_title }
  field :question, **TEXT
  field :keywords, **TEXT
  field :answer, **TEXT
end
