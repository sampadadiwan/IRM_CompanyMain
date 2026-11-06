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

  # ⑩ Compliance hub (R170): /compliance shows the section bar as lazy pill tabs, like the fund page's
  # tabs. Each section pane is a turbo frame named compliance_hub_<section>_frame whose src is the
  # section's own index URL. That URL answers the frame request with just its content inside the
  # frame (no section bar; the frame request has no layout, so no breadcrumbs), and a normal request
  # with the full standalone page. The frame name only picks the rendering; authorization is the
  # action's own (authorize / policy_scope run before this is called).
  # Named compliance_hub_* because compliance_duties_frame etc. are already the inner grids' frames.
  def hub_frame_request?(section)
    turbo_frame_request? && request.headers["Turbo-Frame"] == ComplianceHub.frame_id(section)
  end

  def render_hub_pane(section, template)
    @in_compliance_hub = true
    render partial: "compliance_shared/hub_pane", locals: { section:, template: }
  end
end
