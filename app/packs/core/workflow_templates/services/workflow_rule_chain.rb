# The auto-assignment rules for one entity and one record type, in the order
# WorkflowAutoAssignmentService walks them, with each rule classified by whether it can ever win.
#
# Why this exists: rules are only ever displayed per template (the rules table on a template's page,
# a bare count in the template list), but the thing that decides a record's outcome is the whole
# chain for its type — every rule, across every template, in priority order. That chain had no
# screen, so two different misconfigurations were invisible from the page an admin was working on:
# a rule on a retired template, and a rule sitting behind an identical catch-all it can never beat.
#
# The order here must match the service exactly, or a badge will contradict what actually happens.
# Both order by (priority, id) and both treat a rule whose template is disabled or missing as unable
# to match. Where the service stops at the first rule that applies, this walks the whole chain.
class WorkflowRuleChain
  # One rule's place in the chain.
  #   :active   — can win for some record
  #   :dormant  — its template is disabled, so it stands aside (the rule itself is untouched)
  #   :orphaned — its template row is gone; skipped the same way, and worth saying out loud
  #   :shadowed — an earlier live rule always matches first, so no record can ever reach this one
  # blocker is the rule that shadows it, for :shadowed only.
  Finding = Struct.new(:rule, :status, :blocker, keyword_init: true) do
    def active?   = status == :active
    def shadowed? = status == :shadowed
    def live?     = %i[dormant orphaned].exclude?(status)
  end

  attr_reader :entity, :workflowable_type

  def initialize(entity:, workflowable_type:)
    @entity            = entity
    @workflowable_type = workflowable_type
  end

  # The chain for a rule's own entity and type — what a template's page needs for each of its rules
  def self.for_rule(rule)
    new(entity: rule.entity, workflowable_type: rule.workflowable_type)
  end

  # Every type this template's rules cover, each with its own chain (a template's rules are all one
  # type in practice, but nothing enforces that, so do not assume it)
  def self.for_template(template)
    template.workflow_auto_assignment_rules.map(&:workflowable_type).uniq.map do |type|
      new(entity: template.entity, workflowable_type: type)
    end
  end

  # The rules in evaluation order. Same order as WorkflowAutoAssignmentService#find_matching_rule.
  def rules
    @rules ||= WorkflowAutoAssignmentRule
               .where(entity: entity, workflowable_type: workflowable_type)
               .order(:priority, :id)
               .includes(:workflow_template)
               .to_a
  end

  def findings
    @findings ||= rules.map { |rule| Finding.new(rule: rule, status: status_for(rule), blocker: blocker_for(rule)) }
  end

  def finding_for(rule)
    findings.find { |finding| finding.rule.id == rule.id }
  end

  # The rule that takes over the records `rule` used to be handed — the next live rule down the
  # chain. nil when nothing follows it, which is what makes "this record now gets no workflow" true.
  #
  # Only a catch-all is *certain* to pick up everything the dormant rule matched; a successor with
  # conditions of its own picks up some of those records and leaves the rest with nothing. Callers
  # word the difference from #certain_successor?, because overstating it here would tell an admin
  # their records are covered when they are not.
  def successor_for(rule)
    index = rules.index { |candidate| candidate.id == rule.id }
    return nil unless index

    rules[(index + 1)..].to_a.find { |candidate| live?(candidate) }
  end

  def certain_successor?(rule)
    catch_all?(successor_for(rule))
  end

  # Set when no rule in the chain can assign anything — every one of them is dormant or orphaned.
  # Deliberately narrow: a chain whose live rules merely have conditions is not broken, it is just
  # selective, and warning about it would train admins to ignore the warning.
  def verdict
    return nil if rules.empty?
    return nil if findings.any?(&:active?)

    disabled = findings.reject(&:live?).filter_map { |finding| finding.rule.workflow_template&.name }.uniq
    { reason: :all_dormant, templates: disabled }
  end

  private

  def status_for(rule)
    return :orphaned if rule.workflow_template.nil?
    return :dormant  unless rule.workflow_template.enabled?
    return :shadowed if blocker_for(rule)

    :active
  end

  # The first live rule ahead of this one that always matches whatever it matches: a catch-all, or a
  # rule asking for exactly the same conditions. Nothing else counts — proving that `amount gt 100`
  # swallows `amount gt 500` means reasoning about ten operators, and a badge that wrongly calls a
  # working rule dead is worse than one that misses a dead rule.
  def blocker_for(rule)
    return nil unless live?(rule)

    index = rules.index { |candidate| candidate.id == rule.id }
    return nil unless index

    rules[0...index].find do |earlier|
      live?(earlier) && (catch_all?(earlier) || same_conditions?(earlier, rule))
    end
  end

  def live?(rule)
    rule.workflow_template.present? && rule.workflow_template.enabled?
  end

  def catch_all?(rule)
    rule.present? && Array(rule.conditions).empty?
  end

  def same_conditions?(one, other)
    normalise(one) == normalise(other)
  end

  # Compared as a set of {attribute, operator, value} triples: order within the array does not change
  # which records a rule matches, since #matches? requires all of them.
  def normalise(rule)
    Array(rule.conditions).map { |c| [c["attribute"].to_s, c["operator"].to_s, c["value"].to_s] }.sort
  end
end
