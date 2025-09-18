class FundFormulaDecorator < ApplicationDecorator
  def name
    h.link_to object.name, h.fund_formula_path(object)
  end

  def roll_up
    display_boolean(object.roll_up)
  end

  def enabled
    display_boolean(object.enabled)
  end

  def template_field_name
    h.render partial: "fund_formulas/formula_template_field", locals: { fund_formula: object }, formats: [:html]
  end

  def formula_for
    h.render partial: "fund_formulas/formula_for", locals: { fund_formula: object }, formats: [:html]
  end
end
