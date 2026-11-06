# ⑧ One fact read from a document (or entered by hand), with its quote and page.
# A fact counts toward a result only once a compliance editor confirms it (E66). Every edit and
# confirmation is audited, so the history reads "AI read ₹1.50 cr → Meera set ₹15.00 cr, 06 Nov 2026" (E67).
# Values are typed: text, amount (major units of the pack currency), date (ISO), names (list), yes_no.
# Worked examples H40, H43, E66, E67, E69, X45 — openspec/changes/archive/2026-11-06-fund-compliance-monitoring/business-rules.md
class DocumentFact < ApplicationRecord
  TYPES = %w[text amount date names yes_no].freeze
  STATUSES = %w[ai_read not_found confirmed].freeze
  SOURCES = %w[ai manual].freeze
  MAX_TEXT = 500
  MAX_NAMES = 50

  belongs_to :entity
  belongs_to :document_reading
  belongs_to :confirmed_by, class_name: "User", optional: true

  # Trackable like the app's other audited models (R178); changes and deletions only (R177): the AI-read value
  # is the row as created, and History shows each later edit
  include Trackable.new(on: %i[update destroy], audit_fields: %i[value status source])

  attr_readonly :entity_id, :document_reading_id, :fact_key

  validates :fact_key, presence: true
  validates :value_type, inclusion: { in: TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }
  validate :same_firm_as_reading

  # A raw value (from the AI's reply or a form) as the fact's type; nil when it does not parse.
  # Never evaluated — only parsed as a number, a date, a list of names or yes/no.
  def self.normalize(type, raw)
    return nil if raw.nil? || (raw.respond_to?(:empty?) && raw.empty?)

    case type
    when "amount" then BigDecimal(raw.to_s.delete(",_ ").sub(/\A[^\d-]+/, "")).to_s("F")
    when "date" then Date.parse(raw.to_s).iso8601
    when "names" then (raw.is_a?(Array) ? raw : raw.to_s.split(/[,;\n]/)).map { |n| n.to_s.strip.first(120) }.compact_blank.first(MAX_NAMES)
    when "yes_no" then ActiveModel::Type::Boolean.new.cast(raw.to_s.strip.downcase.sub(/\Ano\z/, "false").sub(/\Ayes\z/, "true"))
    else raw.to_s.strip.first(MAX_TEXT).presence
    end
  rescue ArgumentError, TypeError
    nil
  end

  # Display a typed value: amounts in the pack's currency (₹15.00 cr), dates via the locale format
  def self.display(type, value, currency = "INR")
    return "—" if value.nil? || value == []

    case type
    when "amount" then ComplianceFormat.amount(value.to_d, currency)
    when "date" then I18n.l(Date.parse(value.to_s))
    when "names" then Array(value).join(", ")
    when "yes_no" then value ? "Yes" : "No"
    else value.to_s
    end
  end

  def confirmed?
    status == "confirmed"
  end

  def not_found?
    status == "not_found"
  end

  def typed_value
    case value_type
    when "amount" then value&.to_d
    when "date" then value.present? ? Date.parse(value.to_s) : nil
    when "names" then Array(value)
    else value
    end
  end

  def display_value(currency = "INR")
    not_found? && value.nil? ? "Not found in document" : self.class.display(value_type, value, currency)
  end

  # E66/E67: confirming (optionally with a corrected value) is what lets the fact count
  def confirm!(user, new_value: :unchanged)
    self.value = self.class.normalize(value_type, new_value) unless new_value == :unchanged
    self.status = "confirmed"
    self.confirmed_by = user
    self.confirmed_at = Time.current
    save!
  end

  # E67: "AI read ₹1.50 cr → Meera set ₹15.00 cr, 06 Nov 2026" — from the audits of the value
  def history(currency = "INR")
    # From the loaded audits (callers preload them: document_facts.includes(:audits)) — no query per fact (R176)
    all = audits.to_a.sort_by(&:id)
    # Where the first value came from: `source` is fixed at creation (manual entry or AI read) and
    # never changes, so no create audit is needed to know it (R177)
    origin = source
    edits = all.select { |a| a.action == "update" && a.audited_changes["value"].is_a?(Array) }
    edits.each_with_index.map do |a, i|
      change = a.audited_changes["value"]

      before = if i.zero?
                 origin == "manual" ? "Entered" : "AI read"
               else
                 "Was"
               end
      "#{before} #{self.class.display(value_type, change[0], currency)} → #{a.user&.first_name || 'someone'} set " \
        "#{self.class.display(value_type, change[1], currency)}, #{I18n.l(a.created_at.to_date)}"
    end
  end

  private

  def same_firm_as_reading
    return if document_reading.nil? || document_reading.entity_id == entity_id

    errors.add(:document_reading, "must belong to your firm")
  end
end
