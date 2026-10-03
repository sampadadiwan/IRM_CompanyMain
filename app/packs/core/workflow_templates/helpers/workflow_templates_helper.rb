module WorkflowTemplatesHelper
  # Returns ordered User records for the current entity, used to populate
  # actor select menus in template/step forms.
  def entity_users_for_select
    User.where(entity_id: current_user.entity_id).order(:first_name, :last_name)
  end

  # Confirmation text for the Enable/Disable button, on the template list and the template page.
  # Spells out both halves of the switch, because the half people get wrong is what happens to work
  # that is already under way: nothing. For a journey template it also says what new records lose —
  # the whole journey, since the step bar only exists where an instance was launched.
  #
  # The rules are kept, and they are not inert in isolation: disabling moves the records they matched
  # on to whatever comes next in the chain. That successor is named here, at the moment of the
  # decision, because it is the one consequence an admin cannot see from this page.
  def workflow_template_toggle_message(template)
    unless template.enabled
      return "\"#{template.name}\" will be used again: records created from now on can be assigned " \
             "and launched on it. Records created while it was disabled are not given one retrospectively."
    end

    records = template.workflowable_type.present? ? template.workflowable_type.underscore.humanize.downcase.pluralize : "records"
    journey = template.journey? ? " New #{records} will have no journey at all — no step bar and no task reminders." : ""
    rules = template.workflow_auto_assignment_rules.size
    inert = rules.positive? ? " Its #{pluralize(rules, 'auto-assignment rule')} will be kept but go dormant.#{workflow_template_successor_sentence(template)}" : ""

    "\"#{template.name}\" will no longer be used for new work: it will not be auto-assigned, " \
      "will not appear in the Launch Workflow picker, and cannot be launched.#{inert}#{journey} " \
      "Workflows already running on it carry on exactly as they are — they follow the snapshot taken " \
      "when they launched. You can enable it again at any time."
  end

  # What takes over once this template's rules go dormant. Three outcomes, worded apart because they
  # mean different things to the records involved:
  #   a catch-all successor  — everything the dormant rule matched goes there instead
  #   a conditional one      — some of those records go there, the rest get nothing
  #   nothing live behind it — they get no workflow at all
  def workflow_template_successor_sentence(template)
    # The rule that runs first is the one whose records are most at stake, so its chain is the one to
    # report on — a template's rules are all one type in practice, but nothing enforces that.
    rule  = template.workflow_auto_assignment_rules.min_by { |r| [r.priority, r.id] }
    chain = WorkflowRuleChain.for_rule(rule) if rule
    return "" if chain.blank?

    successor = chain.successor_for(rule)
    return " Records that matched #{rules_pronoun(template)} will then match no other rule, so they will get no workflow." if successor.blank?

    name = successor.workflow_template.name
    if chain.certain_successor?(rule)
      " Records that matched #{rules_pronoun(template)} will fall through to \"#{name}\" instead."
    else
      " Records that matched #{rules_pronoun(template)} will fall through to \"#{name}\" where they also " \
        "meet its conditions, and otherwise get no workflow."
    end
  end

  # Status of one rule in the rules table: whether it can ever win, and when it cannot, why.
  # A shadowed rule's blocker is linked, because it almost always lives on another template's page —
  # which is exactly why shadowing was invisible before.
  def workflow_rule_status_badge(finding)
    return nil if finding.blank? # a rule outside any chain we built — say nothing rather than guess

    case finding.status
    when :active
      tag.span("Active", class: "badge bg-success-subtle text-success border border-success-subtle")
    when :dormant
      tag.span("Dormant", class: "badge bg-secondary-subtle text-secondary border border-secondary-subtle",
                          data: { bs_toggle: "tooltip",
                                  bs_title: "This template is disabled, so the rule is skipped and the " \
                                            "next matching rule for this type applies. It resumes unchanged " \
                                            "when the template is enabled." })
    when :orphaned
      tag.span("No template", class: "badge bg-danger-subtle text-danger border border-danger-subtle",
                              data: { bs_toggle: "tooltip",
                                      bs_title: "This rule points at a template that no longer exists, so it " \
                                                "is skipped. Delete it." })
    when :shadowed
      badge = tag.span("Shadowed",
                       class: "badge bg-warning-subtle text-warning-emphasis border border-warning-subtle",
                       data: { bs_toggle: "tooltip",
                               bs_title: "An earlier rule always matches first, so no record ever reaches " \
                                         "this one. Give the earlier rule conditions, raise its priority " \
                                         "number, or delete it." })
      blocker = tag.span(workflow_rule_blocker_link(finding.blocker), class: "d-block small text-muted mt-1")
      safe_join([badge, blocker])
    end
  end

  # "by <template> (priority N)" — the blocking rule named, and reachable
  def workflow_rule_blocker_link(blocker)
    safe_join(["by ",
               link_to(blocker.workflow_template.name, workflow_template_path(blocker.workflow_template)),
               " (priority #{blocker.priority})"])
  end

  private

  def rules_pronoun(template)
    template.workflow_auto_assignment_rules.size == 1 ? "it" : "them"
  end
end
