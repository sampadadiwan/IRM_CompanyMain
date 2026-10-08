# Who may see and change an entity's Document Checks setup: fund users of an entity with the "Doc LLM
# validation" permission, for their own entity's checks only.
# See openspec/changes/document-checks/design.md (card ① Setup, Access). Worked examples X6, RS1.
class DocCheckPolicy < ApplicationPolicy
  class Scope < Scope
    # Strictly the user's own entity (no group-company widening for configuration)
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    enabled? && !investor?
  end

  # Saving a card, applying a preset, trying on a KYC
  def update?
    index? && (record.is_a?(Class) || belongs_to_entity?(user, record))
  end

  def save_document? = update?
  def add_recommended? = update?
  def trial? = update?
  # The setup page's Import button (ImportUpload type DocCheck); Export is the index as xlsx
  def import? = update?

  private

  def enabled?
    user.entity&.enable_doc_llm_validation
  end

  def investor?
    user.curr_role_investor?
  end
end
