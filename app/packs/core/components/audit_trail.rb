class AuditTrail < ViewComponent::Base
  def initialize(model, title: nil, css_class: "", state: "show", allow_toggle: true, only_keys: nil, graphical: false)
    super()
    @model = model
    @title = title
    @css_class = css_class
    @state = state
    @allow_toggle = allow_toggle
    @only_keys = only_keys
    @graphical = graphical
  end

  def filtered_changes(audit)
    changes = audit.audited_changes
    return changes if @only_keys.blank?

    changes = changes.select { |k, _v| @only_keys.include?(k) }.deep_dup

    # Thoughtful: Humanize IDs
    changes.each do |k, v|
      next unless k.end_with?("_id") && v.is_a?(Array)

      # Try to find the record and its name
      begin
        model_name = k.chomp("_id").classify
        # Only do this if the model exists
        model = model_name.constantize
        v[0] = model.find_by(id: v[0])&.to_s if v[0]
        v[1] = model.find_by(id: v[1])&.to_s if v[1]
      rescue StandardError
        # Fail gracefully, leave as IDs
      end
    end
    changes
  end
end
