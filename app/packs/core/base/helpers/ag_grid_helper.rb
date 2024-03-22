module AgGridHelper
  def get_ag_theme
    # This cookie is set by modernize theme. See public/modernize/app.min.js handleTheme()
    cookies[:theme] == "dark" ? "ag-theme-quartz-dark" : "ag-theme-quartz"
  end
end
