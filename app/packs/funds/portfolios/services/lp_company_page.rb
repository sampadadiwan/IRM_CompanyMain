# What the LP Company Dashboard is about: one portfolio company, seen through one fund, by one viewer (an LP, or
# a fund-team member previewing as an LP). Authorised by LpCompanyDashboardPolicy.
# openspec/changes/lp-folio-portfolio-dashboard/design.md (card ⑥)
LpCompanyPage = Struct.new(:company, :fund, :visibility, :preview_investor, keyword_init: true) do
  def self.policy_class
    LpCompanyDashboardPolicy
  end

  def preview?
    preview_investor.present?
  end
end
