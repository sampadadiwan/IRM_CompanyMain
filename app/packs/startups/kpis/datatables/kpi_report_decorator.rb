class KpiReportDecorator < ApplicationDecorator
  delegate_all

  def dt_actions
    links = []
    links << h.link_to('Show', h.kpi_report_path(object), class: "btn btn-outline-primary")
    links << h.link_to('Edit', h.edit_kpi_report_path(object), class: "btn btn-outline-success") if h.policy(object).edit?
    h.safe_join(links, '')
  end
end
