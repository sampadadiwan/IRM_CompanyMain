# Rule library grid cells (CompliancePack::STANDARD_COLUMNS keys)
class CompliancePackDecorator < ApplicationDecorator
  def name
    h.link_to object.name, h.compliance_pack_path(object)
  end

  # Who owns the pack: a locked CapHive pack, or the firm's own entity pack
  def locked
    if object.caphive?
      h.cmp_badge(object.locked ? "CapHive — locked" : "CapHive", "secondary", :lock)
    else
      h.cmp_badge("Entity pack", "info", :pack)
    end
  end

  def latest_version
    latest = object.latest_published_version
    if latest
      "#{latest.label} · effective #{latest.effective_from ? h.l(latest.effective_from) : '—'}"
    else
      "Draft only"
    end
  end

  def retired_on
    if object.retired?
      h.cmp_badge("Retired #{h.l(object.retired_on)}", "secondary")
    elsif object.latest_published_version
      h.cmp_badge("Published", "success", :publish)
    else
      h.cmp_badge("Draft", "secondary", :edit)
    end
  end
end
