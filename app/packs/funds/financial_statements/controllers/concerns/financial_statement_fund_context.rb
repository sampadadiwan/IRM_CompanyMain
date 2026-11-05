# Shared by the Financial Statements controllers: loads the fund from fund_id (only funds the user
# can see), and sets breadcrumbs and the active tab for the shared tab bar.
module FinancialStatementFundContext
  extend ActiveSupport::Concern

  included do
    # The forms' Cancel links use the same rule as the redirects after save, so a crafted
    # `return_to=javascript:…` can never become a link (features/security/stored_and_reflected_xss.feature, XSS-7)
    helper_method :return_path
  end

  private

  def set_fund_from_params
    @fund = policy_scope(Fund).find(params[:fund_id])
  end

  def fund_breadcrumbs(current)
    @bread_crumbs = { Funds: funds_path, "#{@fund.name}": fund_path(@fund),
                      'Financial Statements': financial_statements_path(fund_id: @fund.id), "#{current}": nil }
  end

  # Back to the tab the form was opened from (only a local path), else the default.
  # A local path starts with exactly one "/". Refused, each with the reason:
  #   "javascript:…", "https://evil.example" — not a path at all
  #   "//evil.example"                       — protocol-relative: the browser goes to evil.example
  #   "/\evil.example"                       — browsers read "\" as "/", so this is "//evil.example" too
  # Every return_to the app builds is request.fullpath, which always passes.
  def return_path(default)
    path = params[:return_to].to_s
    local = path.start_with?("/") && !path.start_with?("//") && !path.start_with?("/\\")
    local ? path : default
  end

  # A date from a form or query string; nil for blank or unreadable input (no 500 on garbage)
  def fs_parse_date(value)
    return nil if value.blank?

    Date.local_parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # The fund's previewed / generated period: from params, else the last completed quarter
  def preview_period
    end_date = fs_parse_date(params[:period_end])
    start_date = fs_parse_date(params[:period_start])
    end_date ||= (Time.zone.today.beginning_of_quarter - 1)
    start_date ||= end_date.beginning_of_quarter
    start_date > end_date ? [end_date.beginning_of_quarter, end_date] : [start_date, end_date]
  end
end
