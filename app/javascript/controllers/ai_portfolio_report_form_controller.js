import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    newInvestorUrl: String
  }

  static targets = [
    "portfolioSelect",
    "addDocumentsLink",
    "existingTemplateSelect",
    "newTemplateForm",
    "templatePreview",
    "criteriaContainer",
    "templateSelect",
    "documentsModal",
    "documentsTable",
    "documentsTableBody",
    "documentsEmpty",
    "uploadArea",
    "uploadBtn",
    "uploadStatus"
  ]


  // Escape HTML to prevent XSS when inserting user-provided content
  escapeHTML(str) {
    const div = document.createElement('div')
    div.textContent = str
    return div.innerHTML
  }

  connect() {
    this.criterionIndex = 1
    this.existingIds = new Set(
      Array.from(this.portfolioSelectTarget.options).map(o => o.value).filter(v => v)
    )

    // Listen for tab visibility changes (returning from investor creation tab)
    document.addEventListener('visibilitychange', this.handleVisibilityChange.bind(this))

    // Pre-select portfolio company from URL param (when coming from documents page)
    const urlParams = new URLSearchParams(window.location.search)
    const preselectedId = urlParams.get('portfolio_company_id')
    if (preselectedId) {
      this.portfolioSelectTarget.value = preselectedId
      this.portfolioSelectTarget.dispatchEvent(new Event('change'))
    }

    // Handle form re-render after validation errors
    this.updateTemplateVisibility()
  }

  disconnect() {
    document.removeEventListener('visibilitychange', this.handleVisibilityChange.bind(this))
  }

  // Called when portfolio company dropdown changes
  portfolioCompanyChanged() {
    this.updateTemplateVisibility()
    this.updateAddDocumentsLink()
  }

  // Called when template_action radio changes
  templateActionChanged() {
    this.updateTemplateVisibility()
  }

  // Open new investor creation in a new tab
  openNewInvestor(event) {
    event.preventDefault()
    window.open(this.newInvestorUrlValue)
  }


  // Preview template via AJAX
  previewTemplate() {
    const templateId = this.hasTemplateSelectTarget ? this.templateSelectTarget.value : null
    if (!templateId) {
      alert('Please select a template first')
      return
    }

    fetch(`/investment_criteria_templates/${templateId}/preview`)
      .then(response => response.json())
      .then(data => {
        let html = '<div class="card mt-2"><div class="card-body p-2">'
        html += `<h6 class="card-title mb-2">${data.name}</h6>`
        html += '<table class="table table-sm table-bordered mb-0">'
        html += '<thead class="table-light"><tr><th style="width: 30%">Criterion</th><th>Evaluation Criteria</th></tr></thead>'
        html += '<tbody>'
        data.criteria.forEach(c => {
          html += `<tr class="small"><td class="py-1"><strong>${c.name}</strong></td><td class="py-1">${c.value}</td></tr>`
        })
        html += '</tbody></table></div></div>'
        this.templatePreviewTarget.innerHTML = html
        this.templatePreviewTarget.style.display = 'block'
      })
      .catch(err => {
        console.error('Preview failed:', err)
        alert('Failed to load template preview')
      })
  }

  // Add a new criterion row
  addCriterion() {
    const row = document.createElement('div')
    row.className = 'criteria-row d-flex mb-2'
    row.innerHTML = `
      <input type="text" name="new_template[criteria][${this.criterionIndex}][name]"
             placeholder="Criterion name" class="form-control mr-2" style="flex: 0.35">
      <input type="text" name="new_template[criteria][${this.criterionIndex}][value]"
             placeholder="What to evaluate" class="form-control mr-2" style="flex: 0.6">
      <button type="button" class="btn btn-danger btn-sm" data-action="click->ai-portfolio-report-form#removeCriterion">×</button>
    `
    this.criteriaContainerTarget.appendChild(row)
    this.criterionIndex++
  }

  // Remove a criterion row
  removeCriterion(event) {
    event.target.closest('.criteria-row').remove()
  }


    // Open documents modal and fetch existing documents
  openDocumentsModal(event) {
    event.preventDefault()
    const investorId = this.portfolioSelectTarget.value
    if (!investorId) return

    // Show modal
    this.modal = new bootstrap.Modal(this.documentsModalTarget)
    this.modal.show()

    // Fetch documents
    this.fetchDocuments(investorId)
  }

  fetchDocuments(investorId) {
    fetch(`/ai_portfolio_reports/evaluation_folder_documents?portfolio_company_id=${investorId}`)
      .then(r => r.json())
      .then(data => {
        this.folderId = data.folder_id
        this.entityId = data.entity_id
        this.refreshDocumentList(data.documents)
      })
      .catch(err => console.error('Failed to fetch documents:', err))
  }

  refreshDocumentList(documents) {
    if (documents.length === 0) {
      this.documentsEmptyTarget.style.display = 'block'
      this.documentsTableTarget.style.display = 'none'
    } else {
      this.documentsEmptyTarget.style.display = 'none'
      this.documentsTableTarget.style.display = 'table'
      this.documentsTableBodyTarget.innerHTML = documents.map(doc => `
        <tr>
          <td>${this.escapeHTML(doc.name)}</td>
          <td>${this.escapeHTML(doc.created_at)}</td>
          <td>
            ${doc.file_url ? `<a href="${this.escapeHTML(doc.file_url)}" target="_blank" class="btn btn-sm btn-outline-primary">View</a>` : '-'}
          </td>
        </tr>
      `).join('')
    }
  }

  uploadDocuments() {
    const investorId = this.portfolioSelectTarget.value
    if (!investorId) return

    // Collect all hidden fields created by the multiple-upload controller
    const fileInputs = this.uploadAreaTarget.querySelectorAll('input[type="hidden"][name*="[file]"]')
    const nameInputs = this.uploadAreaTarget.querySelectorAll('input[type="hidden"][name*="[name]"]')

    if (fileInputs.length === 0) {
      this.uploadStatusTarget.textContent = 'Please select files first.'
      return
    }

    const documents = []
    for (let i = 0; i < fileInputs.length; i++) {
      documents.push({
        name: nameInputs[i] ? nameInputs[i].value : `Document ${i + 1}`,
        file: fileInputs[i].value
      })
    }

    this.uploadBtnTarget.disabled = true
    this.uploadStatusTarget.textContent = 'Uploading...'

    const csrfToken = document.querySelector('meta[name="csrf-token"]').content

    fetch('/ai_portfolio_reports/upload_evaluation_documents', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken
      },
      body: JSON.stringify({
        portfolio_company_id: investorId,
        documents: documents
      })
    })
      .then(r => r.json())
      .then(data => {
        this.refreshDocumentList(data.documents)
        this.uploadStatusTarget.textContent = 'Documents uploaded successfully!'
        this.uploadBtnTarget.disabled = false

        // Clear the hidden fields from the upload area
        this.uploadAreaTarget.querySelectorAll('input[type="hidden"]').forEach(el => el.remove())
      })
      .catch(err => {
        console.error('Upload failed:', err)
        this.uploadStatusTarget.textContent = 'Upload failed. Please try again.'
        this.uploadBtnTarget.disabled = false
      })
  }


  // --- Private methods ---

  updateAddDocumentsLink() {
    if (!this.hasAddDocumentsLinkTarget) return
    const investorId = this.portfolioSelectTarget.value
    this.addDocumentsLinkTarget.style.display = investorId ? 'inline' : 'none'
  }





  updateTemplateVisibility() {
    const selectedRadio = document.querySelector('input[name="template_action"]:checked')
    const hasPortfolioCompany = this.portfolioSelectTarget.value !== ''

    let warningMsg = document.getElementById('template-company-warning')
    if (!warningMsg) {
      warningMsg = document.createElement('div')
      warningMsg.id = 'template-company-warning'
      warningMsg.className = 'alert alert-warning mt-2'
      warningMsg.textContent = 'Please select a Portfolio Company first.'
      this.element.querySelector('.template-selection').appendChild(warningMsg)
    }

    const existingSelect = this.hasExistingTemplateSelectTarget ? this.existingTemplateSelectTarget : null
    const newTemplateForm = this.hasNewTemplateFormTarget ? this.newTemplateFormTarget : null

    if (selectedRadio) {
      if (hasPortfolioCompany) {
        warningMsg.style.display = 'none'
        if (existingSelect) existingSelect.style.display = selectedRadio.value === 'use_existing' ? 'block' : 'none'
        if (newTemplateForm) newTemplateForm.style.display = selectedRadio.value === 'create_new' ? 'block' : 'none'
      } else {
        warningMsg.style.display = 'block'
        if (existingSelect) existingSelect.style.display = 'none'
        if (newTemplateForm) newTemplateForm.style.display = 'none'
      }
    } else {
      warningMsg.style.display = 'none'
      if (existingSelect) existingSelect.style.display = 'none'
      if (newTemplateForm) newTemplateForm.style.display = 'none'
    }
  }

  handleVisibilityChange() {
    if (document.visibilityState !== 'visible') return

    const previousValue = this.portfolioSelectTarget.value

    fetch(window.location.href)
      .then(r => r.text())
      .then(html => {
        const doc = new DOMParser().parseFromString(html, 'text/html')
        const freshSelect = doc.querySelector('select[name="ai_portfolio_report[portfolio_company_id]"]')
        if (!freshSelect) return

        this.portfolioSelectTarget.innerHTML = freshSelect.innerHTML

        // Auto-select newly created company, or restore previous selection
        let newCompanyFound = false
        Array.from(this.portfolioSelectTarget.options).forEach(opt => {
          if (opt.value && !this.existingIds.has(opt.value)) {
            this.portfolioSelectTarget.value = opt.value
            newCompanyFound = true
          }
        })

        if (!newCompanyFound && previousValue) {
          this.portfolioSelectTarget.value = previousValue
        }

        this.portfolioSelectTarget.dispatchEvent(new Event('change'))
      })
  }

}
