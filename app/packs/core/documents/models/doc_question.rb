class DocQuestion < ApplicationRecord
  enum qtype: { validation: "Validation", extraction: "Extraction", general: "General" }
  FOR_CLASSES = %w[InvestorKyc Offer Interest Investor].sort.freeze

  attr_accessor :interpolated_question

  belongs_to :entity
  belongs_to :owner, polymorphic: true

  validates :question, :qtype, :document_name, :for_class, presence: true
  validates :qtype, inclusion: { in: qtypes.keys }
  validates :for_class, length: { maximum: 25 }
  validates :document_name, :question, :response_hint, length: { maximum: 255 }
  validates :qtype, length: { maximum: 10 }

  scope :validations, -> { where(qtype: qtypes[:validation]) }
  scope :extractions, -> { where(qtype: qtypes[:extraction]) }
  scope :generals, -> { where(qtype: qtypes[:general]) }
  scope :for_class, ->(for_class) { where(for_class:) }

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
