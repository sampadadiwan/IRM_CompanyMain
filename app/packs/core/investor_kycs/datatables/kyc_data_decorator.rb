class KycDataDecorator < ApplicationDecorator
  def dt_actions
    links = []
    links << h.link_to('Show', h.kyc_data_path(object), class: "btn btn-outline-primary")
    h.safe_join(links, '')
  end
end
