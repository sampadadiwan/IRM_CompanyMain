# Register grid cells: the same keys as ComplianceRegisterItem::STANDARD_COLUMNS, so sorting uses the
# real columns while the cell shows the check name, badges and links.
class ComplianceRegisterItemDecorator < ApplicationDecorator
  def fund_name
    h.link_to object.fund.name, h.fund_path(object.fund, tab: "compliance-tab")
  end

  def pack_name
    object.fund_compliance_pack.pack_name
  end

  def check_key
    h.link_to object.check_name, h.compliance_register_item_path(object)
  end

  # Fix-by date with an Overdue badge once it has passed (E35)
  def fix_by
    return "—" if object.fix_by.nil?

    parts = [h.l(object.fix_by)]
    parts << h.cmp_badge("Overdue", "danger", :overdue) if object.overdue?
    h.safe_join(parts, " ")
  end

  def assignee_first_name
    object.assignee&.full_name || "—"
  end

  def status
    h.cmp_item_status_badge(object)
  end
end
