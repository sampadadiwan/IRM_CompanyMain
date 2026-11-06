# Breadcrumbs for compliance pages, in the app's @bread_crumbs format (layouts/_breadcrumbs).
#   Firm-level pages:  Compliance › <page> › <record>
#   Fund-scoped pages: Funds › <fund> › Compliance › <page>  (same shape as FundsHelper#fund_bread_crumbs,
#   which reads params[:fund_id] — compliance routes carry the fund on the record instead)
# The last crumb has no link.
module ComplianceCrumbs
  extend ActiveSupport::Concern

  private

  # trail: [[label, path_or_nil], ...] after "Compliance"
  def compliance_crumbs(*trail)
    @bread_crumbs = { Compliance: compliance_home_path }
    trail.each { |label, path| @bread_crumbs[label.to_s] = path }
    last_crumb_unlinked
  end

  def compliance_fund_crumbs(fund, *trail)
    @bread_crumbs = { Funds: funds_path }
    @bread_crumbs[fund.name] = fund_path(fund)
    @bread_crumbs[:Compliance] = fund_path(fund, tab: "compliance-tab")
    trail.each { |label, path| @bread_crumbs[label.to_s] = path }
    last_crumb_unlinked
  end

  def last_crumb_unlinked
    last = @bread_crumbs.keys.last
    @bread_crumbs[last] = nil
  end
end
