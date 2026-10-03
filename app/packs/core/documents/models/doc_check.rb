# One thing the AI reads from one document, for one record type: fill in a field, compare it with a
# field, or answer a yes-no question. Checks hang off (entity, record type, document name); a record
# only gets the checks for the documents on its own list.
# See openspec/changes/document-checks/design.md (card ① Setup).
class DocCheck < ApplicationRecord
  ACTIONS = %w[fill_in compare question].freeze
  ANSWERS = %w[yes no].freeze

  belongs_to :entity
  has_many :doc_check_results, dependent: :nullify

  before_validation :normalise

  validates :record_type, inclusion: { in: ->(_) { DocChecks::Registry.record_types } }
  validates :action, inclusion: { in: ACTIONS }
  validates :document_name, presence: true, length: { maximum: 100 }
  validates :look_for, presence: { message: "Say what to look for" }, length: { maximum: 100 }
  validates :tip, length: { maximum: 255, message: "Keep the tip under 255 characters" }
  validates :expected_answer, inclusion: { in: ANSWERS }
  validate :field_allowed
  # Set by DocChecks::CardForm, which checks the whole card's rows against each other itself (the database
  # can't see unsaved siblings, and would flag two rows swapping fields)
  attr_accessor :card_checked

  # One field per card; a question has no field and is exempt. Worked example E3.
  validates :field_name, uniqueness: { scope: %i[entity_id record_type document_name], message: "Already used on this document" },
                         allow_nil: true, unless: :card_checked
  validates :look_for, uniqueness: { scope: %i[entity_id record_type document_name], message: "Already on this document" },
                       unless: :card_checked

  scope :ordered, -> { order(:position, :id) }

  # The checks that apply to a record: its entity's, for its record type, on the documents of its own
  # list (matched ignoring case). Worked example E6 — openspec/changes/document-checks/design.md#worked-examples
  def self.for_record(record)
    entry = DocChecks::Registry.for(record)
    names = entry.document_names_for(record).map(&:downcase)
    where(entity_id: record.entity_id, record_type: DocChecks::Registry.record_type_of(record))
      .where("LOWER(document_name) IN (?)", names.presence || [""]).ordered
  end

  def fill_in? = action == "fill_in"
  def compare? = action == "compare"
  def question? = action == "question"

  # The key this check's answer comes back under in the AI's reply — never a name the AI chooses.
  # Unsaved checks (the AI rules tool, presets) use their object id.
  def reply_key
    "c#{id || object_id}"
  end

  def entry
    DocChecks::Registry.for(record_type)
  end

  # The registry field this check uses, or nil when it is not (or no longer) allowed
  def field
    return nil if question? || field_name.blank?

    @field = nil if @field && @field.name != field_name
    @field ||= entry.field(entity, field_name)
  end

  # A saved check whose field was removed from the record's form after setup. Worked example E16.
  def field_missing?
    !question? && field.nil?
  end

  private

  def normalise
    self.record_type = record_type.presence || "InvestorKyc"
    self.document_name = document_name.to_s.squish
    self.look_for = look_for.to_s.squish
    self.tip = tip.to_s.squish.presence
    # A question has an expected answer instead of a field; the other actions never do
    self.field_name = nil if question?
    self.field_name = field_name.presence
    self.replace_existing = false unless fill_in?
  end

  # Fill in and Compare need a field from the registry's list. Worked example X4.
  def field_allowed
    return if question?
    return errors.add(:field_name, "Pick a KYC field") if field_name.blank?
    return if entity && DocChecks::Registry.supported?(record_type) && entry.field(entity, field_name)

    errors.add(:field_name, "Pick a KYC field")
  end
end
