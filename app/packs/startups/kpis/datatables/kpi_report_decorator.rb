class KpiReportDecorator < ApplicationDecorator
  delegate_all

  def dt_actions
    links = []
    links << h.link_to('Show', h.kpi_report_path(object), class: "btn btn-outline-primary")
    h.safe_join(links, '')
  end
end
