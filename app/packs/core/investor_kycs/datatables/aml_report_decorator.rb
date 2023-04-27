class AmlReportDecorator < ApplicationDecorator
  def associates
    h.render partial: "/aml_reports/associates", locals: { aml_report: object }, formats: [:html]
  end

  def aml_approved
    h.display_boolean(object.approved)
  end

  def dt_actions
    links = []
    links << h.link_to('Show', h.aml_report_path(object), class: "btn btn-outline-primary")
    h.safe_join(links, '')
  end
end
