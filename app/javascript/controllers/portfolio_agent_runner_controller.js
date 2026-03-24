import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="portfolio-agent-runner"
export default class extends Controller {
  static values = { companyIds: Array, agentId: Number }

  connect() {
    console.log("Portfolio Agent Runner controller connected")
    console.log("Agent ID:", this.agentIdValue)
    console.log("Company IDs:", this.companyIdsValue)

    // Listen for table refresh events from Turbo Stream on the frame itself
    const frame = document.getElementById('portfolio_companies_table')
    if (frame) {
      frame.addEventListener('portfolio-table-refresh', this.handleTableRefresh.bind(this))
    }
  }

  disconnect() {
    const frame = document.getElementById('portfolio_companies_table')
    if (frame) {
      frame.removeEventListener('portfolio-table-refresh', this.handleTableRefresh.bind(this))
    }
  }

  // Handle table refresh event from Turbo Stream broadcast
  handleTableRefresh(event) {
    console.log('Received table refresh event')
    const frame = document.getElementById('portfolio_companies_table')
    if (frame) {
      // Perform a proper GET request to reload the frame
      const currentUrl = new URL(window.location.href)
      const refreshUrl = currentUrl.pathname + currentUrl.search

      console.log('Refreshing frame with URL:', refreshUrl)

      // Use fetch with explicit GET to reload frame content
      fetch(refreshUrl, {
        method: 'GET',
        headers: {
          'Accept': 'text/vnd.turbo-stream.html, text/html, application/xhtml+xml',
          'Turbo-Frame': 'portfolio_companies_table'
        }
      })
      .then(response => response.text())
      .then(html => {
        const parser = new DOMParser()
        const doc = parser.parseFromString(html, 'text/html')
        const newFrame = doc.getElementById('portfolio_companies_table')
        if (newFrame) {
          frame.innerHTML = newFrame.innerHTML
          console.log('Table refreshed successfully')
        }
      })
      .catch(error => {
        console.error('Error refreshing table:', error)
      })
    }
  }

  // Show custom confirmation modal and submit if confirmed
  showConfirmation(event) {
    event.preventDefault()

    const agentId = this.agentIdValue
    const companyCount = this.companyIdsValue.length

    if (companyCount === 0) {
      alert('No companies selected to run the agent on.')
      return
    }

    // Populate the global confirm modal
    $('#confirmModal #title').text('Confirm Agent Execution')
    $('#confirmModal #msg').html(`Run agent on <strong>${companyCount} portfolio companies</strong>?<br><br>This will queue ${companyCount} agent execution(s) in the background.`)

    // Show notification status
    $('#confirmModal #confirm_notification').show()
    $('#confirmModal #confirm_notification_icon').html('<i class="ti ti-bell-check text-success"></i> Yes')

    // Show reversibility warning
    $('#confirmModal #confirm_reversible').show()
    $('#confirmModal #confirm_reversible_icon').html('<i class="ti ti-alert-triangle text-danger"></i> No')

    // Show other info
    $('#confirmModal #confirm_other_info').show()
    $('#confirmModal #confirm_other_info_text').text('Notifications will be sent when the batch completes')

    // Show the details section
    $('#confirmModal #confirm_details').show()

    // Store reference to this controller for the modal's proceed button
    const controller = this

    // Use a namespaced event to avoid interfering with other handlers
    const eventNamespace = 'portfolioAgentRunner'

    // Remove our previous handler if it exists
    $('#confirmModal .btn-outline-success').off(`click.${eventNamespace}`)

    // Attach our handler with namespace
    $('#confirmModal .btn-outline-success').on(`click.${eventNamespace}`, function(e) {
      e.preventDefault() // Prevent form submission
      // Note: Not using stopPropagation to allow other event handlers to work

      $('#confirmModal').modal('hide')

      // Build the request with target IDs (generic for all agent types)
      const actionUrl = `/support_agents/${agentId}/run_batch`

      // Create FormData and add target IDs with type
      const formData = new FormData()
      controller.companyIdsValue.forEach(id => {
        formData.append('target_ids[]', id)
      })
      // For portfolio companies, the target type is Investor
      formData.append('target_type', 'Investor')

      console.log('Submitting to:', actionUrl)
      console.log('Target IDs:', controller.companyIdsValue)
      console.log('Target Type: Investor')

      fetch(actionUrl, {
        method: 'POST',
        headers: {
          'Accept': 'text/vnd.turbo-stream.html',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        },
        body: formData
      })
      .then(response => {console.log('Response', response);return response.text()})
      .then(html => {
        // Turbo will automatically process the turbo-stream response
        Turbo.renderStreamMessage(html)
        console.log('Batch agent run queued successfully')
      })
      .catch(error => {
        console.error('Error submitting batch:', error)
        alert('An error occurred while queuing the agent batch')
      })

      return false // Extra safety to prevent default behavior
    })

    // Clean up our handler when modal is hidden
    $('#confirmModal').one('hidden.bs.modal', function() {
      $('#confirmModal .btn-outline-success').off(`click.${eventNamespace}`)
    })

    // Show the modal
    const modal = new bootstrap.Modal(document.getElementById('confirmModal'))
    modal.show()
  }
}
