import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["responses"]

  async export() {
    console.log("[PptExportController] Exporting to PPT...")

    let PptxGenJS
    try {
      const module = await import("pptxgenjs")
      PptxGenJS = module.default || module
    } catch (e) {
      console.error("[PptExportController] Failed to import pptxgenjs", e)
      PptxGenJS = window.pptxgen || window.PptxGenJS
    }

    if (!PptxGenJS) {
      alert("PptxGenJS library not found. Please ensure it is installed.")
      return
    }

    let pres
    try {
      pres = new PptxGenJS()
    } catch (e) {
      pres = PptxGenJS()
    }

    pres.layout = 'LAYOUT_WIDE'

    const messages = this.responsesTarget.querySelectorAll('.assistant-message-card')

    if (messages.length === 0) {
      alert("No assistant responses found to export.")
      return
    }

    for (const [index, card] of messages.entries()) {
      const prose = card.querySelector('.prose')
      if (!prose) continue

      let currentSlide = pres.addSlide()
      currentSlide.addText(`Response ${index + 1}`, { x: 0.5, y: 0.2, w: 12.33, h: 0.5, fontSize: 18, bold: true, color: '363636' })

      let currentY = 0.8
      const PAGE_W = 13.333
      const PAGE_H = 7.5
      const MARGIN = 0.5

      const blocks = Array.from(prose.children)

      for (const block of blocks) {
        const chartBlock = block.hasAttribute('data-controller') && block.getAttribute('data-controller').includes('chart-renderer')
                          ? block
                          : block.querySelector('[data-controller*="chart-renderer"]')

        if (chartBlock) {
          const canvas = chartBlock.querySelector('canvas')
          if (canvas && canvas.width > 0 && canvas.height > 0) {
            try {
              const imgData = canvas.toDataURL('image/png')
              if (imgData && imgData !== 'data:,') {
                const chartSlide = pres.addSlide()
                chartSlide.addText(`Response ${index + 1} - Chart`, { x: 0.5, y: 0.2, w: 12.33, h: 0.5, fontSize: 18, bold: true, color: '363636' })

                // MAINTAIN ASPECT RATIO
                // Max available space
                const maxWidth = PAGE_W - 1
                const maxHeight = PAGE_H - 1.5

                // Calculate dimensions based on canvas aspect ratio
                const canvasRatio = canvas.width / canvas.height
                const maxRatio = maxWidth / maxHeight

                let finalWidth, finalHeight
                if (canvasRatio > maxRatio) {
                  // Canvas is wider than available space ratio
                  finalWidth = maxWidth
                  finalHeight = maxWidth / canvasRatio
                } else {
                  // Canvas is taller than available space ratio
                  finalHeight = maxHeight
                  finalWidth = maxHeight * canvasRatio
                }

                // Center the image in the remaining space if desired, or just use x=0.5
                const finalX = 0.5 + (maxWidth - finalWidth) / 2

                chartSlide.addImage({
                  data: imgData,
                  x: finalX,
                  y: 0.8,
                  w: finalWidth,
                  h: finalHeight
                })
              }
            } catch (e) {
              console.warn("[PptExportController] Failed to capture chart canvas", e)
            }
            continue
          }
        }

        if (currentY > PAGE_H - MARGIN) {
          currentSlide = pres.addSlide()
          currentSlide.addText(`Response ${index + 1} (cont.)`, { x: 0.5, y: 0.2, w: 12.33, h: 0.5, fontSize: 18, bold: true, color: '363636' })
          currentY = 0.8
        }

        if (block.tagName === 'TABLE') {
          const tableData = this.extractTableData(block)
          if (tableData.length > 0) {
            currentSlide.addTable(tableData, {
              x: 0.5,
              y: currentY,
              w: 12.33,
              autoPage: true,
              fontSize: 10,
              border: { type: 'solid', color: 'E1E1E1', pt: 1 },
              fill: { color: 'F9F9F9' },
              headerContext: { fill: { color: 'EEEEEE' }, bold: true }
            })
            currentY += (tableData.length * 0.3) + 0.5
          }
        } else {
          const text = block.innerText.trim()
          if (text.length > 0) {
            const fontSize = block.tagName.startsWith('H') ? 14 : 11
            const isBold = block.tagName.startsWith('H') || block.tagName === 'STRONG'

            currentSlide.addText(text, {
              x: 0.5,
              y: currentY,
              w: 12.33,
              fontSize: fontSize,
              bold: isBold,
              valign: 'top',
              breakLine: true
            })

            const lines = Math.ceil(text.length / 100)
            currentY += (lines * (fontSize / 72) * 1.5) + 0.2
          }
        }
      }
    }

    const filename = `Assistant_Export_${new Date().toISOString().slice(0, 10)}.pptx`
    await pres.writeFile({ fileName: filename })
    console.log(`[PptExportController] Exported: ${filename}`)
  }

  extractTableData(tableEl) {
    const data = []
    const rows = tableEl.querySelectorAll('tr')
    rows.forEach(row => {
      const rowData = []
      const cells = row.querySelectorAll('th, td')
      cells.forEach(cell => {
        rowData.push(cell.innerText.trim())
      })
      if (rowData.length > 0) data.push(rowData)
    })
    return data
  }
}
