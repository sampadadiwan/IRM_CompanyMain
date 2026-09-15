# Managed FAQs and guide search (docs/ai/guide_faq_search_prd.md).
#
# 1. faq_entries — one row per FAQ question on a user guide. Production is the master copy;
#    `rake guide_faqs:export` snapshots published rows to docs/user_guides/faqs/*.yml.
#    `faq_group` rather than `group`: GROUP is a reserved word in MySQL and SQLite, and
#    ransack and hand-written SQL would both have to remember to quote it.
#
# 2. guide_search_synonyms — ops-managed synonym rules for the chatbot's guide search,
#    in Elasticsearch/Solr synonym syntax ("drawdown, capital call" or "lp => investor").
#
# 3. agent_chat_messages — `guide_search_hit` already existed but nothing ever wrote it.
#    `guide_search_terms` records that a guide search ran at all (so a message that never
#    searched is not counted as a miss), and `guide_search_strong_hit` records whether any
#    result matched at least two-thirds of the search terms (GuideSearch::STRONG_MATCH_RATIO).
class CreateGuideFaqs < ActiveRecord::Migration[8.1]
  def change
    create_table :faq_entries do |t|
      t.string :guide_key, limit: 150, null: false
      t.string :faq_group, limit: 20, null: false
      t.integer :position
      t.string :question, limit: 300, null: false
      t.text :answer, null: false
      t.string :keywords, limit: 500
      t.string :audience, limit: 20, null: false, default: "signed_in"
      t.string :status, limit: 20, null: false, default: "draft"
      t.datetime :published_at
      t.datetime :last_verified_at
      t.boolean :needs_verification, null: false, default: false
      t.json :verification_errors
      t.bigint :source_message_id
      t.bigint :created_by_id
      t.bigint :updated_by_id
      t.timestamps
    end
    change_table :faq_entries, bulk: true do |t|
      t.index %i[guide_key question], unique: true
      t.index %i[guide_key faq_group position]
      t.index :status
      t.index :needs_verification
    end

    create_table :guide_search_synonyms do |t|
      t.string :terms, limit: 500, null: false
      t.boolean :enabled, null: false, default: true
      t.string :note, limit: 255
      t.bigint :updated_by_id
      t.timestamps
    end

    change_table :agent_chat_messages, bulk: true do |t|
      t.boolean :guide_search_strong_hit, null: false, default: false
      t.string :guide_search_terms, limit: 255
    end
  end
end
