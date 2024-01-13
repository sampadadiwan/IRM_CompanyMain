class CustomTable < ViewComponent::Base
  def initialize(data_source:, id:, column_names:, css_class: "")
    super
    @data_source = data_source
    @id = id
    @column_names = column_names.split(",")
    @css_class = css_class
  end
end
