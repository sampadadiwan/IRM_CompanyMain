# ?headline=true (with fund_ratios_only) returns only the headline ratios the fund page shows above its
# Ratios list (FundRatio.headline_ratios) — the LP mobile app's Performance card
rows = params[:headline].present? && @headline_ratios ? @headline_ratios : @fund_ratios
json.array! rows, partial: "fund_ratios/fund_ratio", as: :fund_ratio
