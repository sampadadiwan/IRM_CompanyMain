# Readiness warnings for the capital call journey panel: things that won't stop a task from
# passing but mean some investors won't be emailed. Shown only until notices are sent — after
# that they can't be acted on, and the subscriber lookup they reuse is relatively heavy.
# Worked examples E6, E27 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
module WorkflowChecks
  class CapitalCallWarnings
    include WorkflowChecks::CapitalCall::Support

    def initialize(call)
      @call = call
    end

    # Array of warning strings (possibly empty)
    def to_a
      return [] if notices_not_applicable?(@call) || notices_all_sent?(@call)

      [subscriber_warning, skip_doc_gen_warning].compact
    end

    private

    # Same source as the approve-time validation rule, so the two never disagree
    def subscriber_warning
      names = CapitalCallRuleContextProvider.new.send(:investors_without_notification_subscribers, @call)
      return if names.blank?

      count = names.to_s.split(",").size
      "#{count} #{'investor'.pluralize(count)} #{count == 1 ? 'has' : 'have'} nobody subscribed to Capital Call emails"
    end

    def skip_doc_gen_warning
      count = remittances(@call).where(capital_commitment_id: ::CapitalCommitment.skip_doc_gen_ids(@call.fund.capital_commitments)).count
      return if count.zero?

      "#{count} #{'commitment'.pluralize(count)} #{count == 1 ? 'has' : 'have'} Skip Doc Gen set and will not be emailed"
    end
  end
end
