module EntityScopes
  extend ActiveSupport::Concern

  included do
    default_scope { order(name: :asc) }
    scope :vcs, -> { where(entity_type: "Investor") }
    scope :startups, -> { where(entity_type: "Company") }
    scope :investment_advisors, -> { where(entity_type: "Investment Advisor") }
    scope :investor_advisors, -> { where(entity_type: "Investor Advisor") }
    scope :family_offices, -> { where(entity_type: "Family Office") }
    scope :funds, -> { where(entity_type: "Investment Fund") }
    scope :user_investor_entities, ->(user) { where('access_rights.access_to': user.email).includes(:access_rights) }

    scope :perms, ->(p) { where_permissions(p.to_sym) }
    scope :no_perms, ->(p) { where_not_permissions(p.to_sym) }
  end
end
