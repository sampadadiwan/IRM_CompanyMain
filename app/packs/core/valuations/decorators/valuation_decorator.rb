class ValuationDecorator < ApplicationDecorator
  def investment_instrument_name
    h.link_to object.investment_instrument.name, h.investment_instrument_path(object.investment_instrument) if object.investment_instrument
  end

  def dt_actions
    links = []
    links << h.link_to('Show', h.valuation_path(object), class: "btn btn-outline-primary ti ti-eye")
    links << h.link_to('Edit', h.edit_valuation_path(object), class: "btn btn-outline-success ti ti-trash") if object.import_upload_id.present?
    h.safe_join(links, '')
  end
end
