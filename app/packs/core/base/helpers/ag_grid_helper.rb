module AgGridHelper
  def get_ag_theme
    admin_settings = begin
      JSON.parse(cookies[:adminSettings])
    rescue StandardError
      {}
    end
    admin_settings["Theme"] == "dark" ? "ag-theme-quartz-dark" : "ag-theme-quartz"
  end
end
