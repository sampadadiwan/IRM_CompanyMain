import { Controller } from "@hotwired/stimulus"

console.log("KPI Chart Controller File Loaded")

export default class extends Controller {
  static targets = ["chartContainer", "controlsContainer", "kpiCheckbox", "savedSettingsList", "settingNameInput", "mainControls", "alertModal", "alertModalBody"]
  static values = {
    portfolioCompanyId: String,
    entityId: String,
    refreshUrl: String
  }

  connect() {
    this.selectedKpis = []
    this.chartConfig = []
    this.selectedSettingIds = []
    // Initialize selectedSettingIds from any pre-checked checkboxes
    this.savedSettingsListTarget.querySelectorAll('input[type="checkbox"]:checked').forEach(cb => {
      this.selectedSettingIds.push(cb.value)
    })
  }

  toggleKpi(event) {
    const name = event.target.dataset.kpiName
    if (event.target.checked) {
      if (!this.selectedKpis.includes(name)) {
        this.selectedKpis.push(name)
        this.chartConfig.push({ name: name, type: "line" })
      }
    } else {
      this.selectedKpis = this.selectedKpis.filter(k => k !== name)
      this.chartConfig = this.chartConfig.filter(c => c.name !== name)
    }
    this.refreshControls()
  }

  updateType(event) {
    const name = event.target.dataset.kpiName
    const type = event.target.value
    const config = this.chartConfig.find(c => c.name === name)
    if (config) {
      config.type = type
    } else {
      this.chartConfig.push({ name: name, type: type })
    }
  }

  refreshChart() {
    const formData = new FormData()

    // Send current manual config
    this.chartConfig.forEach((c, index) => {
      formData.append(`chart_config[${index}][name]`, c.name)
      formData.append(`chart_config[${index}][type]`, c.type)
    })

    // Send selected saved setting IDs
    this.selectedSettingIds.forEach((id) => {
      formData.append(`selected_setting_ids[]`, id)
    })

    formData.append("portfolio_company_id", this.portfolioCompanyIdValue)
    formData.append("entity_id", this.entityIdValue)
    formData.append("flexible_chart", "true")

    // Use current URL params if any (like q, tag_list etc)
    const urlParams = new URLSearchParams(window.location.search)
    for (const [key, value] of urlParams.entries()) {
      if (key === "portfolio_company_id" || key === "entity_id" || key === "flexible_chart") continue
      formData.append(key, value)
    }

    // Also explicitly grab values from the filter form if they aren't in the URL yet
    const filterForm = document.getElementById("kpi_reports_filter")
    if (filterForm) {
      ["no_of_periods", "period", "tag_list", "category"].forEach(name => {
        const input = filterForm.querySelector(`[name="${name}"]`)
        if (input && input.value && !formData.has(input.name)) {
          formData.append(input.name, input.value)
        }
      })
    }

    fetch(this.refreshUrlValue, {
      method: "POST",
      headers: {
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      },
      body: formData
    })
    .then(r => r.text())
    .then(html => {
      if (html.length > 0) {
        Turbo.renderStreamMessage(html);
      }
    })
    .catch(error => console.error("Error refreshing chart:", error));
  }

  showAlert(message) {
    if (this.hasAlertModalTarget && this.hasAlertModalBodyTarget) {
      this.alertModalBodyTarget.innerText = message
      const modal = new bootstrap.Modal(this.alertModalTarget)
      modal.show()
    } else {
      window.alert(message)
    }
  }

  saveSetting() {
    const nameInput = this.settingNameInputTarget
    const name = nameInput.value
    if (!name) {
      this.showAlert("Please enter a name for the setting")
      return
    }

    const body = {
      kpi_chart_setting: {
        name: name,
        portfolio_company_id: this.portfolioCompanyIdValue,
        entity_id: this.entityIdValue,
        config: this.chartConfig
      }
    }

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    fetch("/kpi_chart_settings", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": csrfToken
      },
      body: JSON.stringify(body)
    })
    .then(async r => {
      const data = await r.json()
      if (!r.ok) throw data
      return data
    })
    .then(data => {
      this.showAlert("Setting saved successfully!")
      this.refreshSavedSettingsList() // Refresh the HTML list
      nameInput.value = ""
    })
    .catch(error => {
      this.showAlert("Error saving setting: " + JSON.stringify(error))
    })
  }

  toggleSavedSetting(event) {
    const id = event.target.value
    if (event.target.checked) {
      if (!this.selectedSettingIds.includes(id)) {
        this.selectedSettingIds.push(id)
      }
    } else {
      this.selectedSettingIds = this.selectedSettingIds.filter(i => i !== id)
    }
    this.refreshChart()
  }

  // Refresh the HTML list after a new save
  refreshSavedSettingsList() {
    fetch(`/kpi_chart_settings?portfolio_company_id=${this.portfolioCompanyIdValue}&entity_id=${this.entityIdValue}`)
    .then(r => r.json())
    .then(data => {
      this.savedSettingsListTarget.innerHTML = ""
      if (data.length === 0) {
        this.savedSettingsListTarget.innerHTML = '<div class="px-3 small text-muted">No saved settings</div>'
        return
      }
      data.forEach(s => {
        const div = document.createElement("div")
        div.className = "px-3 py-1 dropdown-item-text"
        div.innerHTML = `
          <div class="form-check">
            <input class="form-check-input" type="checkbox" value="${s.id}" id="setting_${s.id}"
                   ${this.selectedSettingIds.includes(String(s.id)) ? 'checked' : ''}
                   data-action="change->kpi-chart#toggleSavedSetting click->kpi-chart#stopProp">
            <label class="form-check-label small" for="setting_${s.id}" data-action="click->kpi-chart#stopProp">
              ${s.name}
            </label>
          </div>
        `
        this.savedSettingsListTarget.appendChild(div)
      })
    })
  }

  stopProp(event) {
    event.stopPropagation()
  }

  updateCheckboxes() {
    this.kpiCheckboxTargets.forEach(cb => {
      cb.checked = this.selectedKpis.includes(cb.dataset.kpiName)
    })
  }

  refreshControls() {
    if (this.selectedKpis.length === 0) {
      this.controlsContainerTarget.innerHTML = ""
      this.mainControlsTarget.classList.add("d-none")
      return
    }

    this.mainControlsTarget.classList.remove("d-none")
    let html = '<div class="row">'
    this.chartConfig.forEach(c => {
      html += `
        <div class="col-md-4 mb-2">
          <label class="form-label text-truncate d-block" title="${c.name}">${c.name}</label>
          <select class="form-select form-select-sm" data-action="change->kpi-chart#updateType" data-kpi-name="${c.name}">
            <option value="line" ${c.type === 'line' ? 'selected' : ''}>Line</option>
            <option value="column" ${c.type === 'column' ? 'selected' : ''}>Bar</option>
            <option value="area" ${c.type === 'area' ? 'selected' : ''}>Area</option>
            <option value="pie" ${c.type === 'pie' ? 'selected' : ''}>Pie</option>
            <option value="donut" ${c.type === 'donut' ? 'selected' : ''}>Donut</option>
          </select>
        </div>
      `
    })
    html += '</div>'

    this.controlsContainerTarget.innerHTML = html
  }

  clearAll() {
    this.selectedKpis = []
    this.chartConfig = []
    this.selectedSettingIds = []
    this.updateCheckboxes()
    this.refreshControls()
    this.refreshSavedSettingsList()
    this.refreshChart()
  }

  addAll() {
    this.selectedSettingIds = []
    this.savedSettingsListTarget.querySelectorAll('input[type="checkbox"]').forEach(cb => {
      this.selectedSettingIds.push(cb.value)
      cb.checked = true
    })
    this.refreshChart()
  }
}
