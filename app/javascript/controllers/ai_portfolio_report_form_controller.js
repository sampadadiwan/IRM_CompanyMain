import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    investorFolders: Object,
    newInvestorUrl: String
  }

  static targets = [
    "portfolioSelect",
    "manageDocumentsLink",
    "existingTemplateSelect",
    "newTemplateForm",
    "templatePreview",
    "criteriaContainer",
    "templateSelect"
  ]

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
    this.updateManageDocumentsLink()
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

  // Open manage documents in a new tab
  openDocuments(event) {
    event.preventDefault()
    window.open(this.manageDocumentsLinkTarget.dataset.href)
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

  // --- Private methods ---

  updateManageDocumentsLink() {
    if (!this.hasManageDocumentsLinkTarget) return
    const investorId = this.portfolioSelectTarget.value
    const folders = this.investorFoldersValue

    if (investorId && folders[investorId]) {
      const info = folders[investorId]
      this.manageDocumentsLinkTarget.dataset.href = '/documents/folder?folder_id=' + info.folder_id
      this.manageDocumentsLinkTarget.style.display = 'inline'
    } else {
      this.manageDocumentsLinkTarget.style.display = 'none'
    }
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

    fetch(window.location.href)
      .then(r => r.text())
      .then(html => {
        const doc = new DOMParser().parseFromString(html, 'text/html')
        const freshSelect = doc.querySelector('select[name="ai_portfolio_report[portfolio_company_id]"]')
        if (!freshSelect) return

        this.portfolioSelectTarget.innerHTML = freshSelect.innerHTML

        // Update investorFolders from re-fetched page data attribute
        const freshController = doc.querySelector('[data-ai-portfolio-report-form-investor-folders-value]')
        if (freshController) {
          try {
            this.investorFoldersValue = JSON.parse(freshController.dataset.aiPortfolioReportFormInvestorFoldersValue)
          } catch(e) {}
        }

        // Auto-select newly created company
        Array.from(this.portfolioSelectTarget.options).forEach(opt => {
          if (opt.value && !this.existingIds.has(opt.value)) {
            this.portfolioSelectTarget.value = opt.value
          }
        })

        this.portfolioSelectTarget.dispatchEvent(new Event('change'))
      })
  }
}
