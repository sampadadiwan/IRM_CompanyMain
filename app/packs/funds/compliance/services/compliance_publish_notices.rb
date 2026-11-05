# ⑨ H49: owners of every entity whose funds carry the pack are told on publish (entity packs: own firm).
module CompliancePublishNotices
  module_function

  def call(version)
    pack = version.compliance_pack
    entity_ids = pack.caphive? ? FundCompliancePack.active.where(compliance_pack_id: pack.id).distinct.pluck(:entity_id) : [pack.entity_id]
    message = "#{pack.name} #{version.label} published — takes effect on #{I18n.l(version.effective_from)}"
    Entity.where(id: entity_ids).find_each do |entity|
      ComplianceNotices.version_notice(entity, message)
      setup = ComplianceEntitySetup.for(entity)
      setup.update!(digest_notes: Array(setup.digest_notes) + [message])
    end
  end
end
