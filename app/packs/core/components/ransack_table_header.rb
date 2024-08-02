class RansackTableHeader < ViewComponent::Base
  include Ransack::Helpers::FormHelper

  def initialize(model, q:, entity: nil, id: "", css_class: "")
    super
    @model = model
    @q = q.presence || @model.ransack
    @id = id
    @columns = get_columns(entity)
    @css_class = css_class
  end

  attr_accessor :columns

  def get_columns(entity)
    if entity.nil?
      @model::STANDARD_COLUMNS
    else
      custom_grid_view = entity.form_types.find_by(name: @model.to_s)&.custom_grid_view
      return @model::STANDARD_COLUMNS if custom_grid_view.blank?

      custom_grid_view.selected_columns
    end
  end
end
