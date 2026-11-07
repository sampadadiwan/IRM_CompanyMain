# Saves a widget's settings and size from the settings popup on a dashboard.
# openspec/changes/dashboard-widget-inline-settings — design D2, D3; worked examples H3–H5, E3–E6, X4, X5
#
# The target is either a saved widget, or an unsaved default widget (a dashboard whose layout has no enabled
# widget shows the catalogue defaults). Saving a default first saves every default the page shows, so the
# dashboard does not lose its other widgets (a layout with saved widgets shows only those).
class DashboardWidgetSettingsSave
  Result = Struct.new(:widget, :refresh, :errors, keyword_init: true) do
    def success? = errors.empty?
  end

  def self.call(...)
    new(...).call
  end

  def initialize(user:, target:, metadata:, size:)
    @user = user
    @target = target
    @metadata = metadata.to_s.strip
    @size = size.to_s
  end

  def call
    # X5 — only the sizes the widget form offers
    return failure("Size is not one of #{DashboardWidget::SIZES.join(', ')}") unless DashboardWidget::SIZES.include?(@size)

    widget = nil
    refresh = :widget
    errors = []
    ActiveRecord::Base.transaction do
      if @target.new_record?
        # D3 — serialise first saves per firm, then look again: another save may have saved the defaults (E6)
        @entity = Entity.lock.find(@user.entity_id)
        if layout_widgets.none?
          save_defaults
          # D5 — positions were just assigned, so the page refreshes as a whole
          refresh = :page
        end
        widget = layout_widgets.order(:position).find_by(widget_name: @target.widget_name)
        if widget.nil?
          errors << "This dashboard has changed since you opened it. Reload the page and try again."
          raise ActiveRecord::Rollback
        end
      else
        widget = @target
      end

      # E3 — a blank setting is left out by the form, so the widget falls back to its default;
      # X4 — the model refuses settings that are not plain values (metadata_must_be_literal)
      widget.assign_attributes(metadata: @metadata.presence, size: @size)
      unless widget.save
        errors.concat(widget.errors.full_messages)
        # Undo the defaults saved above too: nothing is half-saved
        raise ActiveRecord::Rollback
      end
    end

    return failure(*errors) if errors.any?

    Result.new(widget:, refresh:, errors: [])
  end

  private

  # The layout's enabled widgets — the same test the dashboard uses to decide between saved and default widgets
  def layout_widgets
    DashboardWidget.enabled.where(entity_id: @user.entity_id, dashboard_name: @target.dashboard_name, name: @target.name)
  end

  # H5, E4 — exactly the default set the page shows, in the order shown, with the catalogue's size and settings
  def save_defaults
    DashboardWidget.default_widgets_for(@target.dashboard_name).each_with_index do |definition, index|
      # The locked entity row is passed in, so each widget does not load it again (no N+1)
      DashboardWidget.create!(entity: @entity, dashboard_name: @target.dashboard_name, name: @target.name,
                              widget_name: definition.widget_name, size: definition.size, tags: definition.widget_name,
                              metadata: definition.metadata, position: index + 1, enabled: true, display_name: true,
                              show_menu: true)
    end
  end

  # The form is shown again for the original target (a saved row created in the rolled-back transaction no longer
  # exists), with what the user entered and the reasons
  def failure(*messages)
    @target.assign_attributes(metadata: @metadata.presence, size: @size)
    messages.each { |message| @target.errors.add(:base, message) unless @target.errors.full_messages.include?(message) }
    Result.new(widget: @target, refresh: nil, errors: messages)
  end
end
