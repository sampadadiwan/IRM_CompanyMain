class RansackTableHeader < ViewComponent::Base
  include Ransack::Helpers::FormHelper

  def initialize(q:, entity: nil, id: "", css_class: "")
    super
    @q = q
    @id = id
    @columns = get_columns(entity)
    @css_class = css_class
  end

  attr_accessor :columns

  def get_columns(entity)
    if entity.nil?
      @q.klass::STANDARD_COLUMNS
    else
      custom_grid_view = entity.form_types.find_by(name: @q.klass.to_s)&.custom_grid_view
      return @q.klass::STANDARD_COLUMNS if custom_grid_view.blank?

      custom_grid_view.selected_columns
    end
  end
end
