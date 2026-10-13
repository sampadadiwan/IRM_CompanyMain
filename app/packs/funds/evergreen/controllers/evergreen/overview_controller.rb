# The Overview now lives on the fund page (stats row + details card); old links land there.
module Evergreen
  class OverviewController < BaseController
    def show
      authorize @fund, :show?
      redirect_to fund_path(@fund)
    end
  end
end
