module ValidationRuleOverridesHelper
  # Coloured badge for warning / blocker severity
  def render_severity_badge(severity)
    case severity.to_s
    when "blocker"
      content_tag(:span, "Blocker", class: "badge", style: "background-color:#f87171;color:#7f1d1d")
    when "warning"
      content_tag(:span, "Warning", class: "badge", style: "background-color:#f59e0b;color:#fff")
    else
      content_tag(:span, severity.to_s.titleize, class: "badge bg-secondary")
    end
  end

  # Inline summary of what an override changes (used in both table and card layouts)
  def render_override_summary(override)
    return content_tag(:span, "Using global default", class: "text-muted") unless override

    return content_tag(:span, "Rule disabled", class: "text-muted small") unless override.enabled

    parts = []
    parts << content_tag(:div, safe_join(["Severity: ", render_severity_badge(override.severity_override)]), class: "mb-1") if override.severity_override.present?
    override.param_overrides&.each do |k, v|
      parts << content_tag(:div, safe_join([content_tag(:code, k), ": ", content_tag(:strong, v.to_s)]))
    end
    parts << content_tag(:div, "Custom message set", class: "text-muted", style: "font-size:0.8rem") if override.message_override.present?
    parts << content_tag(:span, "No changes", class: "text-muted") if parts.empty?

    safe_join(parts)
  end

  # Enabled/Disabled badge reflecting the effective status for this entity
  def render_status_badge(override)
    # An override with enabled=false disables the rule; everything else (no override, or enabled=true) is active
    if override.present? && !override.enabled
      content_tag(:span, "Disabled", class: "badge", style: "background-color:#6b7280;color:#fff")
    else
      content_tag(:span, "Enabled", class: "badge", style: "background-color:#22c55e;color:#fff")
    end
  end

  # Edit+Reset or Set Override action buttons (used in both table and card layouts)
  def render_override_actions(override, rule)
    if override
      safe_join([
                  link_to("Edit", edit_validation_rule_override_path(override), class: "btn btn-sm btn-outline-primary me-1"),
                  button_to("Reset", validation_rule_override_path(override),
                            method: :delete, class: "btn btn-sm btn-outline-secondary",
                            form: { data: { turbo_confirm: "Remove this override? The rule will revert to its global default." } })
                ])
    else
      link_to("Set Override", new_validation_rule_override_path(validation_rule_id: rule.id), class: "btn btn-sm btn-outline-secondary")
    end
  end
end
