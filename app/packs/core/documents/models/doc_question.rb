class DocQuestion < ApplicationRecord
  FOR_CLASSES = %w[InvestorKyc Offer Interest Investor].sort.freeze

  attr_accessor :interpolated_question

  belongs_to :entity
  belongs_to :owner, polymorphic: true
  enum :qtype, {
    validation: "Validation",
    extraction: "Extraction",
    general: "General"
  }

  validates :question, :qtype, :for_class, presence: true
  validates :qtype, inclusion: { in: qtypes.keys }
  validates :for_class, length: { maximum: 25 }
  validates :document_name, :question, :response_hint, length: { maximum: 255 }
  validates :qtype, length: { maximum: 10 }
  validates :tags, length: { maximum: 100 }

  scope :validations, -> { where(qtype: qtypes[:validation]) }
  scope :extractions, -> { where(qtype: qtypes[:extraction]) }
  scope :generals, -> { where(qtype: qtypes[:general]) }
  scope :with_for_class, ->(klass) { where(for_class: klass) }

  validate :name_or_tags_present

  def name_or_tags_present
    if document_name.blank? && tags.blank?
      errors.add(:document_name, "Name or Tags must be present") if document_name.blank?
      errors.add(:tags, "Name or Tags must be present") if tags.blank?
    end
  end

  def to_s
    question
  end

  def response_hint_text
    if response_hint.present?
      response_hint
    else
      validation? ? "Answer in Yes or No only. The key is the Question asked without the Response Format Hint" : "The key is the Question asked without the Response Format Hint"
    end
  end
end
