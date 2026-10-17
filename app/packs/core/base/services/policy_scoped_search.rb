# Keeps only the Elasticsearch hits that the user's own list would show (B4-4).
#
# The module search boxes (deals, deal investors, notes, tasks, investors, KYC data, offers,
# secondary sales) filtered Elasticsearch by entity only, so an employee - or an advisor working
# as staff - saw every matching record of the company, past the per-record access rights their
# lists apply. Each hit is now checked against Pundit's policy_scope for its model.
#
# The hits keep their type and order (AR records or Chewy wrappers - whatever the action already
# rendered), so the index views are unaffected; a page of results may just hold fewer rows.
# Company admins see the same results as before (their scope is the whole entity).
# Worked example B4-4 — openspec/changes/fix-tenant-isolation-batch2/report.md#verification
class PolicyScopedSearch
  # @param user  [User]
  # @param model [Class] the ActiveRecord model whose policy scope decides visibility
  # @param hits  [Enumerable] search hits responding to #id
  # @return [Array] the hits the user's policy scope contains, in their original order
  def self.restrict(user, model, hits)
    # Chewy returns nil for an indexed id whose row no longer exists.
    list = hits.to_a.compact
    ids = list.map { |hit| hit.id.to_i }
    return [] if ids.empty?

    # One query: which of these ids the user's list would show.
    allowed = Pundit.policy_scope!(user, model).where(id: ids).distinct.pluck(:id).to_set
    list.select { |hit| allowed.include?(hit.id.to_i) }
  end
end
