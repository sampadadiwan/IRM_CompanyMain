module InvestorsGrantedAccess
  extend ActiveSupport::Concern

  def investor_users(metadata = nil)
    User.joins(investor_accesses: :investor).where("investor_accesses.approved=? and investor_accesses.entity_id=?", true, entity_id).merge(Investor.owner_access_rights(self, metadata))
  end

  def investors_granted_access(metadata = nil)
    Investor.owner_access_rights(self, metadata)
  end
end
