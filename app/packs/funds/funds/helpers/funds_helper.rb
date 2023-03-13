module FundsHelper
  def fund_bread_crumbs(current = nil)
    @bread_crumbs = { Funds: funds_path }
    @bread_crumbs[Fund.find(params[:fund_id]).name] = fund_path(params[:fund_id]) if params[:fund_id]
    @bread_crumbs[current] = nil if current
  end
end
