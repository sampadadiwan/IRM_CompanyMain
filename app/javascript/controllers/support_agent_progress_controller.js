import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    reportId: Number,
    supportAgentId: Number,
    collapsed: { type: Boolean, default: false }
  }

  static targets = ["panelBody", "collapseIcon"]

  connect() {
    console.log("SupportAgentProgress connected", this.reportIdValue)
  }

  togglePanel(event) {
    // Don't toggle if clicking on buttons
    if (event.target.closest('button') || event.target.closest('form')) {
      return
    }

    this.collapsedValue = !this.collapsedValue
    this.updatePanelVisibility()
  }

  updatePanelVisibility() {
    if (this.hasPanelBodyTarget) {
      this.panelBodyTarget.classList.toggle('d-none', this.collapsedValue)
    }
    if (this.hasCollapseIconTarget) {
      this.collapseIconTarget.classList.toggle('ti-chevron-right', this.collapsedValue)
      this.collapseIconTarget.classList.toggle('ti-chevron-down', !this.collapsedValue)
    }
  }

  async run(event) {
  event.preventDefault()
  event.stopPropagation()
  
  // Expand panel when running
  this.collapsedValue = false
  this.updatePanelVisibility()
  
  // Get form and submit via fetch
  const form = event.target.closest('form')
  const url = form.action
  const token = document.querySelector('meta[name="csrf-token"]')?.content
  
  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Accept': 'text/vnd.turbo-stream.html',
        'X-CSRF-Token': token
      }
    })
    
    if (response.ok) {
      const html = await response.text()
      Turbo.renderStreamMessage(html)
    } else {
      const text = await response.text()
      alert('Failed to start agent')
    }
  } catch (error) {
    console.error('Error starting agent:', error)
  }
}

cancel(event) {
    if (!confirm("Cancel this agent run?")) {
      event.preventDefault()
    }
  }

  async toggleStepDetails(event) {
  const stepNum = event.currentTarget.dataset.stepNum
  const container = document.getElementById(`step_details_container_${this.reportIdValue}`)
  if (!container) return

  const existing = document.getElementById(`step_details_${stepNum}`)
  if (existing) {
    existing.remove()
    return
  }

  // Show loading spinner
  container.innerHTML = '<div class="text-center py-2"><span class="spinner-border spinner-border-sm"></span> Loading...</div>'

  try {
    const response = await fetch(`/support_agents/${this.supportAgentIdValue}/step_details?report_id=${this.reportIdValue}&step_num=${stepNum}`, {
      headers: {
        'Accept': 'text/html',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
      }
    })

    if (response.ok) {
      const html = await response.text()
      container.innerHTML = html
    } else {
      container.innerHTML = '<div class="alert alert-warning py-2">Could not load step details</div>'
    }
  } catch (error) {
    console.error('Error fetching step details:', error)
    container.innerHTML = '<div class="alert alert-danger py-2">Error loading step details</div>'
  }
}


  hideStepDetails() {
    const container = document.getElementById(`step_details_container_${this.reportIdValue}`)
    if (container) container.innerHTML = ''
  }
}
