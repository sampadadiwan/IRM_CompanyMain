# ⑨ Sends the daily digest to each owner — nothing on a quiet day (E45). One-off notes are cleared once sent.
class ComplianceDigestJob < ApplicationJob
  queue_as :low

  def perform(entity_id, as_of)
    entity = Entity.find(entity_id)
    date = Date.parse(as_of.to_s)
    setup = ComplianceEntitySetup.for(entity)
    return if setup.last_digest_on && setup.last_digest_on >= date

    digest = ComplianceDigest.new(entity, date).call
    ComplianceNotices.owners(entity).each { |user| ComplianceNotices.digest(entity, user, digest.summary, digest.lines, date) } unless digest.empty?
    setup.update!(last_digest_on: date, digest_notes: [])
  end
end
