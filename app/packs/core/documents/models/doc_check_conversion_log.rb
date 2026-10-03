# A legacy Doc Question that support reviewed and did NOT convert, with the reason. Lets the retirement
# migration tell "skipped on purpose" from "never looked at". Dropped with doc_questions.
# See openspec/changes/document-checks/design.md (Converting the legacy questions).
class DocCheckConversionLog < ApplicationRecord
  belongs_to :entity

  validates :doc_question_id, presence: true, uniqueness: true
  validates :reason, presence: true, length: { maximum: 255 }
end
