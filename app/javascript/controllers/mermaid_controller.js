import { Controller } from "@hotwired/stimulus"
import mermaid from "mermaid"

export default class extends Controller {
  connect() {
    console.log("Mermaid controller connected")
    mermaid.initialize({
      startOnLoad: false,
      theme: 'default',
      securityLevel: 'loose',
    })
    this.render()
  }

  async render() {
    // Find all potential mermaid blocks
    // We look for:
    // 1. <pre><code class="language-mermaid">
    // 2. <pre class="mermaid">
    // 3. <code> class="mermaid"
    // 4. Any <pre> block containing mermaid keywords
    const elements = this.element.querySelectorAll("pre code.language-mermaid, pre code.mermaid, pre.mermaid, code.mermaid, pre")
    
    console.log("Checking elements for mermaid content:", elements.length)

    for (const el of elements) {
      let pre, code
      
      if (el.tagName === "PRE" && el.classList.contains("mermaid")) {
        pre = el
        code = el.textContent
      } else if (el.tagName === "CODE" && el.classList.contains("mermaid") && el.parentElement.tagName === "PRE") {
        pre = el.parentElement
        code = el.textContent
      } else if (el.classList.contains("language-mermaid") && el.parentElement.tagName === "PRE") {
        pre = el.parentElement
        code = el.textContent
      } else if (el.tagName === "PRE") {
        // Check if the content looks like mermaid
        const text = el.textContent.trim()
        if (text.startsWith("sequenceDiagram") || text.startsWith("graph ") || text.startsWith("flowchart ")) {
          pre = el
          code = text
        } else {
          continue
        }
      } else {
        continue
      }

      if (pre) {
        const container = document.createElement("div")
        container.classList.add("mermaid")
        container.textContent = code.trim()
        pre.replaceWith(container)
      }
    }
    
    // Fallback: search for raw text blocks that Redcarpet might have missed
    const paragraphs = this.element.querySelectorAll("p")
    paragraphs.forEach(p => {
      const text = p.textContent.trim()
      if (text.includes("sequenceDiagram") || text.includes("graph TD") || text.includes("flowchart TD")) {
        console.log("Found potential raw mermaid block in paragraph")
        const code = text.replace(/```mermaid|```/g, "").trim()
        const container = document.createElement("div")
        container.classList.add("mermaid")
        container.textContent = code
        p.replaceWith(container)
      }
    })

    // Give the DOM a moment to settle
    setTimeout(async () => {
      try {
        // Use the imported mermaid object
        const m = mermaid.default || mermaid
        console.log("Mermaid object:", m)
        
        if (typeof m.run === 'function') {
          console.log("Running mermaid.run()")
          await m.run()
        } else if (typeof m.init === 'function') {
          console.log("Running mermaid.init()")
          await m.init()
        } else if (typeof m.contentLoaded === 'function') {
          console.log("Running mermaid.contentLoaded()")
          m.contentLoaded()
        } else {
          console.error("No valid mermaid render function found")
        }
      } catch (error) {
        console.error("Mermaid rendering failed:", error)
      }
    }, 200)
  }
}
