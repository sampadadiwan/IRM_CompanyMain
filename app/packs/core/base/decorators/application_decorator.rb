class ApplicationDecorator < Draper::Decorator
  include CurrencyHelper

  delegate_all

  delegate :display_boolean, to: :h
  delegate :money_to_currency, to: :h
  delegate :custom_format_number, to: :h

  def display_date(val)
    h.l(val) if val
  end

  def fund_link
    h.link_to object.fund.name, object.fund
  end

  def investor_link
    h.link_to object.investor_name, h.investor_path(id: object.investor_id)
  end
end
