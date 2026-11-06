# ⑧ One read of one document version for one pack input (design › Document reading and facts).
# Status: queued → read | failed, or capped (monthly cap) → queued next month; "manual" when a person
# entered the facts by hand and nothing was sent to AI (H43). A reading is superseded (derived) when a
# newer reading exists for the same document and input. Facts belong to the reading, so they follow the
# document wherever it is attached (R10, E129).
# Worked examples H40, H43, H45, E68, E74, E75, E130, X45, X46 — openspec/changes/archive/2026-11-06-fund-compliance-monitoring/business-rules.md
class DocumentReading < ApplicationRecord
  STATUSES = %w[queued capped read failed manual].freeze
  WAITING = %w[queued capped].freeze

  belongs_to :entity
  belongs_to :document
  has_many :document_facts, -> { order(:id) }, dependent: :destroy, inverse_of: :document_reading

  attr_readonly :entity_id, :document_id, :input_key

  validates :status, inclusion: { in: STATUSES }
  validates :input_key, :file_checksum, :facts_signature, presence: true
  validate :document_in_same_firm

  # Readings sent to AI this calendar month — the monthly cap counts these (E75)
  scope :sent_in_month, ->(entity_id, at) { where(entity_id:, sent_at: at.all_month) }

  # Facts-to-confirm grid (RansackTable); display values come from DocumentReadingDecorator
  STANDARD_COLUMNS = {
    "Document; text-col" => "document_name; text-col",
    "Input; text-col" => "input_key; text-col",
    "Status; text-col" => "status; text-col",
    "Read on; date-col" => "sent_at; date-col",
    "Waiting since; date-col" => "created_at; date-col"
  }.freeze

  COLUMN_HELP = {
    "input_key" => "Which kind of document the pack reads facts from (e.g. IC note)",
    "status" => "AI reads each document once; a fact counts in compliance checks only after a person confirms it",
    "sent_at" => "When the document was sent to the AI. Blank while it waits (queued, or over the monthly cap)",
    "created_at" => "When the document was picked up for reading — the digest counts the days facts have waited from here"
  }.freeze

  def self.ransackable_attributes(_auth_object = nil)
    %w[created_at input_key sent_at status].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[document]
  end

  # Stored file id + size: a replaced file is a new version and is read again (E68).
  # The file is never downloaded to decide this.
  def self.checksum_for(document)
    data = document.file_data.is_a?(String) ? (JSON.parse(document.file_data.presence || "{}") rescue {}) : document.file_data.to_h # rubocop:disable Style/RescueModifier
    Digest::SHA256.hexdigest("#{data['id']}|#{data.dig('metadata', 'size')}|#{document.id}")
  end

  # Hash of the declared fact keys — a version that adds a fact gives a new signature (R17, E130)
  def self.signature_for(fact_keys)
    Digest::SHA256.hexdigest(Array(fact_keys).map(&:to_s).sort.join(","))
  end

  # The newest reading of each document for an input (older ones are superseded)
  def self.current_for(document_ids, input_key)
    ids = where(document_id: document_ids, input_key:).group(:document_id).maximum(:id).values
    where(id: ids).includes(:document_facts).index_by(&:document_id)
  end

  def waiting?
    WAITING.include?(status)
  end

  def facts_by_key
    document_facts.index_by(&:fact_key)
  end

  def unconfirmed_count
    document_facts.count { |f| !f.confirmed? }
  end

  # "AI-read — 6 facts to confirm" (H40)
  def summary
    case status
    when "queued" then "Waiting to be read"
    when "capped" then "Waiting — monthly reading cap reached"
    when "failed" then "Could not read document"
    else
      n = unconfirmed_count
      prefix = status == "manual" ? "Entered by hand" : "AI-read"
      n.zero? ? "#{prefix} — all facts confirmed" : "#{prefix} — #{n} fact#{'s' if n != 1} to confirm"
    end
  end

  private

  def document_in_same_firm
    return if document.nil? || document.entity_id == entity_id

    errors.add(:document, "must belong to your firm")
  end
end
