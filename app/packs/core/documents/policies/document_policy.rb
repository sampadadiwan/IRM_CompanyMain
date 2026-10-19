class DocumentPolicy < ApplicationPolicy
  def index?
    user.enable_documents || support?
  end

  def bulk_actions?
    index?
  end

  def show?
    # Stray import zips are for the fund's audit trail only - never shown outside the owning entity
    return false if record.import_archive? && !belongs_to_entity?(user, record) && !user.support?

    record.public_visibility ||
      (
        user.enable_documents && belongs_to_entity?(user, record) &&
        (user.has_cached_role?(:company_admin) || (record.owner.present? && owner_policy.show? && !record.folder.private))
      ) ||
      # Cheap checks first: show_investor? runs a multi-join query that is discarded for a
      # switched-in advisor anyway.
      (user.enable_documents && !user.investor_advisor? && show_investor?) ||
      (owner_visible? && !record.folder.private && not_generated_or_approved)
  end

  # Optional per-request memo of "can this user see that owner?", keyed by [owner_type, owner_id].
  # A list of a client's documents has many documents per owner (one commitment, one fund), so
  # DocumentPolicy.ids_a_switched_advisor_can_open shares one memo across the whole list.
  attr_writer :owner_visibility

  def owner_visible?
    return false if record.owner.blank?

    key = [record.owner_type, record.owner_id]
    return @owner_visibility[key] if @owner_visibility&.key?(key)

    visible = owner_policy.show?
    @owner_visibility[key] = visible if @owner_visibility
    visible
  end

  # B3 (b), "documents follow funds": the ids, out of `relation`, that an advisor switched into a
  # client can actually OPEN. Their list (Document.for_investor) used to show everything shared
  # with the client investor - with a 7-day download link per row - while show? (above) only lets
  # a switched advisor open a document whose owner they can see (e.g. a commitment in a fund they
  # were given) or a public one. Filtering the list through show? makes the two the same rule, by
  # construction. Runs only for switched advisors; the candidate set is one client's documents.
  # Worked examples B3-1, B3-H — openspec/changes/fix-tenant-isolation-batch2/report.md#verification
  def self.ids_a_switched_advisor_can_open(user, relation)
    candidate_ids = relation.unscope(:order, :select).select("documents.id")
    # Memoised on the user object (current_user lives for one request): a folder page builds this
    # list more than once (the folder gate, then the documents).
    cache = user.instance_variable_get(:@switched_advisor_document_ids) ||
            user.instance_variable_set(:@switched_advisor_document_ids, {})
    cache_key = [user.entity_id, candidate_ids.to_sql]
    return cache[cache_key] if cache.key?(cache_key)

    owner_visibility = {}
    # Full rows: Document's after_initialize reads columns beyond what show? needs, so a narrowed
    # select raises MissingAttributeError. The set is one client's shared documents, in batches.
    cache[cache_key] = Document.where(id: candidate_ids)
                               .includes(:folder, :owner).find_each.filter_map do |document|
      policy = new(user, document)
      policy.owner_visibility = owner_visibility
      document.id if policy.show?
    end
  end

  def not_generated_or_approved
    # Signed docs (completed esign flow) are never "pending approval" even though they have from_template_id set.
    # Use subject_to_approval? which already excludes signed docs, instead of checking from_template_id directly.
    !record.subject_to_approval? || record.approved
  end

  def create?
    # D: a document lands in its folder's firm, so the folder must be the user's firm's (employees) or the
    # owner's firm's (uploads through an owner, including an outside deal investor)
    (user.enable_documents && permissioned_employee?(:update) && parent_in_users_firms?(record.folder)) ||
      (record.owner && owner_policy.update? && folder_in_owners_firm?) ||
      # The DealInvestor/CapitalCommitment are cases where other users can attach documents to the document owner which is not created by them
      (record.owner && record.owner_type == "DealInvestor" && owner_policy.show? && folder_in_owners_firm?)
    # || (record.owner && record.owner_type == "CapitalCommitment" && owner_policy.show?)
  end

  def new?
    create?
  end

  def download?
    index?
  end

  def update?
    (
      permissioned_employee?(:update) ||
      (record.owner && owner_policy.update?) ||
      allow_external?(:write)
    ) && !record.locked # Ensure locked documents cannot be changed
  end

  # remove user check in next iteration - only check email
  def send_for_esign?
    update? && !record.sent_for_esign && record.e_signatures.all? { |esign| esign.email.present? } && !record.esign_expired? && record.approved
  end

  def resend_for_esign?
    update? && record.resend_for_esign?
  end

  def force_send_for_esign?
    update? && record.sent_for_esign && record.e_signatures.all? { |esign| esign.email.present? } && user.has_cached_role?(:company_admin)
  end

  def send_all_for_esign?
    user.enable_documents && user.has_cached_role?(:company_admin)
  end

  def cancel_esign?
    update? && user.has_cached_role?(:company_admin) && record.sent_for_esign && !record.esign_expired? && !record.esign_failed? && !record.esign_voided?
  end

  def fetch_esign_updates?
    res = update? && record.sent_for_esign && !record.esign_expired? && !record.esign_failed? && !record.esign_voided?
    if record.entity.entity_setting.esign_provider == "Docusign" && !Rails.env.test?
      # hit the docusign api every 15 minutes
      eligible_for_update = record.last_status_updated_at.nil? || record.last_status_updated_at < 900.seconds.ago
      res && eligible_for_update
    else
      res
    end
  end

  def edit?
    update?
  end

  def approve?
    update? && record.to_be_approved? && user.has_cached_role?(:approver)
  end

  def unapprove?
    update? && record.approved && user.has_cached_role?(:approver)
  end

  # SECURITY (finding H7): publishing a document (public_visibility makes show? return true for
  # any user, beyond the owning entity) is a privileged action limited to company admins — not
  # every user who can edit the document. Enforced server-side in DocumentsController on both
  # create and update, so it cannot be flipped via mass assignment.
  def set_public_visibility?
    update? && user.has_cached_role?(:company_admin)
  end

  def destroy?
    (permissioned_employee?(:destroy) &&
    !record.signed? && # cannot delete signed documents
    (!record.sent_for_esign || record.esign_expired? || record.esign_failed? || record.esign_voided?)) || support?
  end

  def show_investor?
    not_generated_or_approved && Document.for_investor(user, record.entity)
                                         .where("documents.id=?", record.id).first.present?
  end

  def send_document_notification?
    update?
  end

  def show_email_list?
    update?
  end

  def verify_accessibility?
    show?
  end

  # AI "Fix Me" on a template: gated to company admins (the same tier who
  # manages templates) since it edits legal document templates, even though
  # the result is always a new draft — the source template is never overwritten.
  # Named to match the DocumentsController#run_fix action (Pundit infers the
  # policy method from the action name via the bare `authorize @document` in
  # set_document).
  def run_fix?
    update? && record.template? && user.has_cached_role?(:company_admin)
  end

  private

  # A document uploaded through its owner lands in the owner's firm: a folder of any other firm is refused
  def folder_in_owners_firm?
    owner_firm = record.owner.is_a?(Entity) ? record.owner.id : record.owner.try(:entity_id)
    # No folder named (it is set from the owner on save), or an owner with no firm: nothing to compare
    return true if record.folder.nil? || owner_firm.nil?

    record.folder.entity_id == owner_firm
  end
end
