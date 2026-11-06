# Duties grid cells (ComplianceDuty::STANDARD_COLUMNS keys)
class ComplianceDutyDecorator < ApplicationDecorator
  def fund_name
    object.fund_compliance_pack.fund.name
  end

  # Duty name; kind-4 duties carry the AI's notes, which the person checks before marking done (H44)
  def duty_key
    parts = [object.name]
    if object.ai_notes.present?
      parts << h.tag.div(class: "small text-muted ai-notes") do
        h.safe_join([h.cmp_icon(:ai), "AI notes (prepared for you — check before marking done): ", object.ai_notes])
      end
    end
    h.safe_join(parts)
  end

  def period_key
    object.period_key.presence || "—"
  end

  def due_on
    object.due_on ? h.l(object.due_on) : "—"
  end

  def owner_first_name
    object.owner&.full_name || "Compliance owner"
  end

  def done_on
    h.cmp_duty_badge(object)
  end
end
