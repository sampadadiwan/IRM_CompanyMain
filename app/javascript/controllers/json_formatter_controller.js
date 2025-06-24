import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textarea"]

  connect() {
    this.formatJson();
  }

  formatJson() {
    const textarea = this.textareaTarget;
    try {
      const parsedJson = JSON.parse(textarea.value);
      textarea.value = JSON.stringify(parsedJson, null, 2);
    } catch (e) {
      // Do nothing if the content is not valid JSON
      console.warn("Content is not valid JSON, skipping formatting.", e);
    }
  }
}