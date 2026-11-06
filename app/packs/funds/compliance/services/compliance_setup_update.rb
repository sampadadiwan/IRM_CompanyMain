# ② Applies a setup form: group mappings, document mappings, per-fund figures, dated reference lists,
# owner, time zone and the monitoring switch (blocked while an input is missing — X15).
# Every change is audited on the setup (Setup › History — H56, R3).
class ComplianceSetupUpdate
  Result = Struct.new(:error, :notice, keyword_init: true) do
    def success?
      error.nil?
    end
  end

  def self.call(setup:, params:, user:)
    new(setup, params, user).call
  end

  def initialize(setup, params, user)
    @setup = setup
    @params = params
    @user = user
  end

  def call
    apply_mappings
    apply_fund_figures
    apply_reference_lists
    @setup.owner_id = @params[:owner_id] if @params.key?(:owner_id)
    @setup.time_zone = @params[:time_zone] if @params[:time_zone].present?
    notice = toggle_ai_drafting || toggle_ai_reading || toggle_monitoring
    return Result.new(error: @blocked) if @blocked
    return Result.new(error: @setup.errors.full_messages.to_sentence) unless @setup.save

    Result.new(notice: notice || "Setup saved")
  end

  private

  # {"sponsor" => "Sponsor, Promoter"} or {"ic_note" => {"tag" => "IC Note"}}
  def apply_mappings
    (@params[:mappings] || {}).each do |key, value|
      value = value.to_h if value.respond_to?(:to_h) && !value.is_a?(String)
      mapping = value.is_a?(Hash) ? value.slice("tag", "name") : { "categories" => value.to_s.split(",").map(&:strip).compact_blank }
      @setup.set_mapping(key, mapping)
    end
  end

  # {"est_expenses" => {"<fund_id>" => "300000000"}} — only funds of the firm
  def apply_fund_figures
    (@params[:fund_figures] || {}).each do |key, per_fund|
      per_fund.to_h.each do |fund_id, value|
        fund = Fund.find_by(id: fund_id, entity_id: @setup.entity_id)
        @setup.set_fund_figure(key, fund, value) if fund
      end
    end
  end

  # {"ic_members" => {"quorum" => "3", "entries" => [{"name","valid_from","valid_to"}]}}
  # or, from the Setup page's list editor, {"excluded_sectors" => {"names" => "Tobacco\nGambling"}}: one name
  # per line; a name already on the list keeps its dates (E14)
  def apply_reference_lists
    (@params[:reference_lists] || {}).each do |key, list|
      list = list.to_h
      entries = if list.key?("names")
                  existing = Array(@setup.reference_lists_hash.dig(key.to_s, "entries")).index_by { |e| e["name"] }
                  list["names"].to_s.lines.map(&:strip).compact_blank.uniq.map { |n| existing[n] || { "name" => n } }
                else
                  Array(list["entries"].is_a?(Hash) ? list["entries"].values : list["entries"]).map(&:to_h).select { |e| e["name"].present? }
                end
      # The list editor sends names only: an existing quorum is kept
      @setup.set_reference_list(key, entries:, quorum: list["quorum"].presence || @setup.reference_lists_hash.dig(key.to_s, "quorum"))
    end
  end

  # X41: the entity's AI-drafting switch for "Describe in words" (ai_settings["drafting"])
  def toggle_ai_drafting
    return nil unless @params.key?(:ai_drafting)

    on = ActiveModel::Type::Boolean.new.cast(@params[:ai_drafting])
    @setup.ai_settings = @setup.ai_settings_hash.merge("drafting" => on)
    on ? "Describe in words on" : "Describe in words off"
  end

  # E74: AI document reading per document input (ai_settings["reading"][key]); off by default.
  # Turning it on starts the hourly sweep from now — older documents are read with Read now (H45).
  def toggle_ai_reading
    return nil unless @params.key?(:ai_reading)

    reading = (@setup.ai_settings_hash["reading"] || {}).dup
    labels = []
    @params[:ai_reading].to_h.each do |key, value|
      input = ComplianceDocumentInputs.find(@setup.entity, key)
      next if input.nil?

      reading[key.to_s] = ActiveModel::Type::Boolean.new.cast(value)
      labels << "#{input.label} reading #{reading[key.to_s] ? 'on' : 'off'}"
    end
    settings = @setup.ai_settings_hash.merge("reading" => reading)
    settings["reading_swept_at"] ||= Time.current.iso8601
    @setup.ai_settings = settings
    labels.to_sentence.presence
  end

  def toggle_monitoring
    return nil unless @params.key?(:monitoring_enabled)

    on = ActiveModel::Type::Boolean.new.cast(@params[:monitoring_enabled])
    if on && !@setup.monitoring_enabled
      @setup.save! if @setup.changed?
      missing = ComplianceInputs.missing_labels(@setup.entity)
      if missing.any?
        @blocked = "#{missing.size} input#{'s' if missing.size != 1} missing — #{missing.join(', ')}"
        return nil
      end
      @setup.owner_id ||= @user.id
      @setup.monitoring_since = Time.zone.today
    end
    @setup.monitoring_enabled = on
    on ? "Monitoring on — first run tonight" : "Monitoring off"
  end
end
