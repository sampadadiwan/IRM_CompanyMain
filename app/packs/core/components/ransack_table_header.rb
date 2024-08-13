class RansackTableHeader < ViewComponent::Base
  include Ransack::Helpers::FormHelper
  include ApplicationHelper

  def initialize(model, q:, entity: nil, current_user: nil, records: nil, id: "", css_class: "")
    super
    @model = model
    @q = q.presence || @model.ransack
    @id = id
    @current_user = current_user
    @entity = entity.presence || get_owner_entity(records)
    @css_class = css_class
  end

  attr_accessor :columns, :entity, :current_user

  def get_columns(entity)
    entity.nil? ? @model::STANDARD_COLUMNS : fetch_custom_columns(entity)
  end

  private

  def fetch_custom_columns(entity)
    form_type = entity.form_types.includes(:grid_view_preferences)
                      .find_by(name: @model.to_s)
    form_type&.selected_columns
  end

  def get_owner_entity(records)
    owner_entity(records, current_user)
  end
end
