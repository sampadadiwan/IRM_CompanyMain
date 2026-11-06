# ⑩ Compliance › Customer setup (E192, X91, R156): which firms with Compliance switched on are still
# setting up, and the step they are on, so CapHive support can reach firms that are stuck. Reads only the
# firm's name and the computed step counts — no fund, investor or figure columns.
class ComplianceOnboardingController < ApplicationController
  include ComplianceCrumbs

  Row = Struct.new(:firm, :done, :total, :next_step, :since, keyword_init: true)

  def index
    authorize :compliance_onboarding, :index?
    setups = policy_scope(ComplianceEntitySetup, policy_scope_class: ComplianceOnboardingPolicy::Scope)
             .includes(:entity).order(:created_at).select { |s| ComplianceAccess.entity_enabled?(s.entity) }
    @rows = setups.map do |s|
      gs = ComplianceGettingStarted.call(entity: s.entity, user: current_user)
      Row.new(firm: s.entity.name, done: gs.done_count, total: gs.steps.size, next_step: gs.current&.label, since: s.created_at.to_date)
    end
    compliance_crumbs(["Customer setup", nil])
  end
end
