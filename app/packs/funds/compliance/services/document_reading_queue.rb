# ⑧ Decides which documents are sent to AI, once per document version, within the entity's opt-in and
# monthly cap (design › Cap and opt-in):
#   enqueue  — one document for one input; idempotent on (document, input, file checksum, facts signature)
#   sweep    — hourly: documents mapped to an enabled input that were uploaded or replaced since the last
#              sweep (H40, E68), readings made before a version added a fact (R17, E130), and capped
#              readings once the month or the cap allows (E75)
#   read_now — an older document a person asks to read (H45), or a retry after a failed read (X46)
# Nothing here calls AI: DocumentFactReadJob does, one reading at a time.
# No hook is added to Document uploads: the hourly sweep finds new and replaced files (R80).
# Worked examples H40, H45, E68, E74, E75, E130, X46 — openspec/changes/fund-compliance-monitoring/business-rules.md
class DocumentReadingQueue
  DEFAULT_CAP = 200
  # How far back the first sweep looks after reading is switched on (older files use Read now — H45)
  FIRST_SWEEP_LOOKBACK = 1.hour

  Result = Struct.new(:reading, :error, keyword_init: true)

  def self.enabled?(setup, input_key)
    setup.ai_settings_hash.dig("reading", input_key.to_s) == true
  end

  def self.cap(setup)
    (setup.ai_settings_hash["reading_cap"].presence || DEFAULT_CAP).to_i
  end

  # Readings sent to AI this month vs the cap (E75)
  def self.within_cap?(setup, at = Time.current)
    DocumentReading.sent_in_month(setup.entity_id, at).count < cap(setup)
  end

  # Queue a read of one document for one input. Returns the reading (existing or new), or nil when the
  # input declares nothing to read or reading is off for it (E74).
  def self.enqueue(document, input_key, setup: ComplianceEntitySetup.for(document.entity), input: nil)
    input ||= ComplianceDocumentInputs.find(document.entity, input_key)
    return nil if input.nil? || !enabled?(setup, input_key) || document.file_data.blank?

    attrs = { document_id: document.id, input_key: input_key.to_s, file_checksum: DocumentReading.checksum_for(document),
              facts_signature: input.signature }
    existing = DocumentReading.find_by(attrs)
    return existing if existing # read once per version

    reading = DocumentReading.create!(attrs.merge(entity_id: document.entity_id, status: "queued", byte_size: file_size(document)))
    DocumentFactReadJob.perform_later(reading.id)
    reading
  rescue ActiveRecord::RecordNotUnique
    DocumentReading.find_by(attrs)
  end

  # H45 / X46: a person asks to read now — a new version is queued; a failed read is retried
  def self.read_now(document, input_key)
    setup = ComplianceEntitySetup.for(document.entity)
    input = ComplianceDocumentInputs.find(document.entity, input_key)
    return Result.new(error: "No pack asks to read this document") if input.nil?
    return Result.new(error: "Reading is not enabled for #{input.label}") unless enabled?(setup, input_key)
    return Result.new(error: "The document has no file") if document.file_data.blank?

    reading = enqueue(document, input_key, setup:, input:)
    if reading&.status == "failed"
      reading.update!(status: "queued", failure_reason: nil)
      DocumentFactReadJob.perform_later(reading.id)
    end
    Result.new(reading:)
  end

  # Hourly (ComplianceScheduleJob): new/replaced documents, stale signatures, capped readings
  def self.sweep(setup, now: Time.current)
    new(setup, now).sweep
  end

  def self.file_size(document)
    data = document.file_data.is_a?(String) ? JSON.parse(document.file_data) : document.file_data.to_h
    data.dig("metadata", "size")
  rescue JSON::ParserError
    nil
  end

  def initialize(setup, now)
    @setup = setup
    @entity = setup.entity
    @now = now
  end

  def sweep
    inputs = ComplianceDocumentInputs.for(@entity).select { |key, _| self.class.enabled?(@setup, key) }
    queued = 0
    inputs.each_value do |input|
      queued += sweep_new_documents(input)
      queued += requeue_stale_signatures(input)
    end
    release_capped
    @setup.update!(ai_settings: @setup.ai_settings_hash.merge("reading_swept_at" => @now.iso8601))
    queued
  end

  private

  def since
    at = @setup.ai_settings_hash["reading_swept_at"]
    at.present? ? Time.zone.parse(at) - 5.minutes : @now - FIRST_SWEEP_LOOKBACK
  end

  # Documents mapped to the input (tag or name), uploaded or replaced since the last sweep
  def sweep_new_documents(input)
    mapping = @setup.document_mapping(input.key)
    return 0 if mapping.nil?

    scope = Document.where(entity_id: @entity.id, owner_type: ComplianceDocumentInputs::OWNER_TYPES).where(updated_at: since..)
    scope = if mapping["tag"].present?
              scope.where("documents.tag_list LIKE ?", "%#{Document.sanitize_sql_like(mapping['tag'])}%")
            else
              scope.where(name: mapping["name"])
            end
    count = 0
    scope.find_each do |doc|
      count += 1 if self.class.enqueue(doc, input.key, setup: @setup, input:)&.previously_new_record?
    end
    count
  end

  # E130: a version added a fact — the documents already read for this input are read again (within the cap)
  def requeue_stale_signatures(input)
    ids = DocumentReading.where(entity_id: @entity.id, input_key: input.key).group(:document_id).maximum(:id).values
    stale = DocumentReading.where(id: ids).where.not(facts_signature: input.signature).where.not(status: "manual")
    count = 0
    stale.includes(:document).find_each do |reading|
      next if reading.document.nil?

      count += 1 if self.class.enqueue(reading.document, input.key, setup: @setup, input:)&.previously_new_record?
    end
    count
  end

  # E75: capped readings go back to the queue when the month turns or the cap is raised
  def release_capped
    room = self.class.cap(@setup) - DocumentReading.sent_in_month(@entity.id, @now).count -
           DocumentReading.where(entity_id: @entity.id, status: "queued").count
    return if room <= 0

    DocumentReading.where(entity_id: @entity.id, status: "capped").order(:id).limit(room).each do |reading|
      reading.update!(status: "queued")
      DocumentFactReadJob.perform_later(reading.id)
    end
  end
end
