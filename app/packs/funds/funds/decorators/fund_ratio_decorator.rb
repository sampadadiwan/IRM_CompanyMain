class FundRatioDecorator < ApplicationDecorator
  def owner_name
    h.link_to object.owner if object.owner
  end

  def fund_name
    h.link_to object.fund.name, h.fund_path(object.fund)
  end

  def name
    link = h.link_to object.name, h.fund_ratio_path(object)
    # What the ratio measures, next to its name
    help = FundRatio.help_for(object.name)
    return link unless help

    h.safe_join([link, " ", h.tag.i(class: "ti ti-info-circle text-muted", data: { bs_toggle: "tooltip" }, title: help, aria: { label: help })])
  end

  def scenario
    case object.computation_context_type
    when "PortfolioScenario"
      h.link_to(
        object.scenario,
        h.portfolio_scenario_path(object.computation_context_id),
        class: 'mb-1 badge bg-primary-subtle text-primary'
      )
    when "FundRatioRun"
      h.link_to(
        object.computation_context.to_s,
        h.fund_ratio_run_path(object.computation_context_id),
        class: 'mb-1 badge bg-primary-subtle text-primary'
      )
    else
      object.scenario
    end
  end

  def dt_actions
    links = []
    links << h.link_to('Show', h.fund_ratio_path(object), class: "btn btn-outline-primary ti ti-eye")
    links << h.link_to('Edit', h.edit_fund_ratio_path(object), class: "btn btn-outline-success ti ti-trash") if object.import_upload_id.present?
    h.safe_join(links, '')
  end
end
