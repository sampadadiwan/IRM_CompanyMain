# ⑧ Reads one queued document with AI (the only place document reading calls AI — LLD › Jobs).
# Re-checks the entity's opt-in and the monthly cap at run time; over the cap the reading waits as
# "capped" until the month turns or the cap is raised (E74, E75). Idempotent: a reading that is no
# longer queued is left alone on retry.
# Worked examples H40, E74, E75, X46 — openspec/changes/fund-compliance-monitoring/business-rules.md
class DocumentFactReadJob < ApplicationJob
  queue_as :low

  def perform(reading_id)
    reading = DocumentReading.find_by(id: reading_id)
    return if reading.nil? || reading.status != "queued" || reading.document.nil?

    # X69: no reading for a firm without Compliance
    unless ComplianceAccess.entity_enabled?(reading.entity)
      Rails.logger.info("[DocumentFactReadJob] reading #{reading_id}: Compliance is off for the entity — skipped")
      return
    end

    setup = ComplianceEntitySetup.for(reading.entity)
    # E74: switched off after it was queued — nothing is sent
    return unless DocumentReadingQueue.enabled?(setup, reading.input_key)

    # E75: one reading at a time per entity passes the cap check (row lock on the setup)
    allowed = setup.persisted? ? setup.with_lock { claim(reading, setup) } : claim(reading, setup)
    return unless allowed

    DocumentFactReader.call(reading)
  end

  private

  def claim(reading, setup)
    unless DocumentReadingQueue.within_cap?(setup)
      reading.update!(status: "capped")
      return false
    end
    # Counted against the cap from this moment (the reader records the model and time sent)
    reading.update!(sent_at: Time.current)
    true
  end
end
