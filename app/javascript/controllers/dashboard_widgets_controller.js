import { Controller } from "@hotwired/stimulus"
import { get } from "@rails/request.js"

export default class extends Controller {
  // Define targets and values for the Stimulus controller
  static targets = ["select"]
  static values = {
    url: String, // URL to fetch data from
    param: String, // Parameter name to send in the request
  }

  /**
   * Called when the controller is connected to the DOM.
   * Sets up event listeners, initializes widget options, and populates widgets if a dashboard is pre-selected.
   */
  connect() {
    console.log(this.urlValue);
    console.log(this.paramValue);

    // Attach a change event listener to the widget dropdown using jQuery
    $("#widget_name").on('change', (event) => {
      console.log("dashboard_widgets_controller: select");
      this.change(event); 
    });

    // Cache references to DOM elements
    this.dashboardNameElement = document.getElementById("dashboard_name")
    this.widgetNameElement = document.getElementById("widget_name")
    this.widgetOptionsJsonElement = document.getElementById("widget_options_json")
    this.selectedWidgetNameElement = document.getElementById("selected_widget_name")
    
    // Initialize widget options and selected widget name
    this.widgetOptions = {}
    this.selectedWidgetName = null

    // Parse widget options JSON if available
    if (this.widgetOptionsJsonElement) {
      try {
        this.widgetOptions = JSON.parse(this.widgetOptionsJsonElement.value)
      } catch (error) {
        console.error("Failed to parse widget options JSON", error)
      }
    }

    // Retrieve the pre-selected widget name if available
    if (this.selectedWidgetNameElement) {
      this.selectedWidgetName = this.selectedWidgetNameElement.value
    }

    // Attach a change event listener to the dashboard dropdown
    if (this.dashboardNameElement) {
      this.dashboardNameElement.addEventListener("change", (e) => this.updateWidgetOptions(e.target.value))
    }

    // 🔥 If a dashboard_name is already selected, populate widget options immediately
    if (this.dashboardNameElement.value) {
      this.updateWidgetOptions(this.dashboardNameElement.value)
    }
  }

  /**
   * Handles the change event for the widget dropdown.
   * Sends a GET request with the selected widget and dashboard name as parameters.
   * 
   * @param {Event} event - The change event triggered by the widget dropdown.
   */
  change(event) {
    console.log(this.urlValue);

    // Construct query parameters
    let params = new URLSearchParams();
    params.append(this.paramValue, event.target.selectedOptions[0].value);
    params.append("dashboard_name", $("#dashboard_name").val());

    // Send a GET request with Turbo Stream response
    get(`${this.urlValue}?${params}`, {
      responseKind: "turbo-stream"
    });
  }

  /**
   * Updates the widget dropdown options based on the selected dashboard.
   * Clears existing options and populates new ones from the widgetOptions map.
   * 
   * @param {string} dashboardName - The name of the selected dashboard.
   */
  updateWidgetOptions(dashboardName) {
    if (!dashboardName || !this.widgetOptions[dashboardName]) return;

    // Clear current widget options
    this.widgetNameElement.innerHTML = ""

    // Add default prompt option
    const promptOption = document.createElement("option")
    promptOption.value = ""
    promptOption.textContent = "Select Widget"
    this.widgetNameElement.appendChild(promptOption)

    // Populate the new options
    this.widgetOptions[dashboardName].forEach(widgetName => {
      const option = document.createElement("option")
      option.value = widgetName
      option.textContent = widgetName
      console.log("widgetName", widgetName);
      console.log("this.selectedWidgetName", this.selectedWidgetName);

      // 🧠 If matches pre-selected widget, mark as selected
      if (widgetName === this.selectedWidgetName) {
        option.selected = true
      }

      this.widgetNameElement.appendChild(option)
    })
  }
}
