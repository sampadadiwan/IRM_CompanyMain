import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    // Only show copy-to-all on the first nested-fields form
    const allForms = document.querySelectorAll(".nested-fields");
    const copyLinks = document.querySelectorAll(".copy-to-all-link");

    copyLinks.forEach((link) => {
      const form = link.closest(".nested-fields");
      if (form !== allForms[0]) {
        link.style.display = "none";
      }
    });
  }

  copyToAll(event) {
    event.preventDefault();

    // Get the current nested form container
    const currentForm = this.element.closest(".nested-fields");
    if (!currentForm) {
      console.error("Could not find nested form container");
      return;
    }

    // Get all the values from the current form
    const sourceData = this.extractFormData(currentForm);

    // Get all other nested forms (siblings)
    const parentContainer = currentForm.parentElement;
    const allForms = parentContainer.querySelectorAll(".nested-fields");

    // Copy data to all other forms
    allForms.forEach((form) => {
      if (form !== currentForm) {
        this.populateFormData(form, sourceData);
      }
    });
  }

  toggleAllDetails(event) {
    event.preventDefault();

    // Get ALL collapse rows across all forms
    const allCollapses = document.querySelectorAll(".nested-fields .collapse");

    let anyExpanded = false;

    // Check if any collapse is currently shown
    allCollapses.forEach((collapse) => {
      if (collapse.classList.contains("show")) {
        anyExpanded = true;
      }
    });

    // Toggle all: collapse all if any are expanded, otherwise expand all
    allCollapses.forEach((collapse) => {
      if (anyExpanded) {
        collapse.classList.remove("show");
      } else {
        collapse.classList.add("show");
      }
    });

    // Update all button icons
    const allButtons = document.querySelectorAll(".nested-fields button[data-action*='toggleAllDetails']");
    allButtons.forEach((button) => {
      const icon = button.querySelector("i");
      if (icon) {
        if (anyExpanded) {
          // Collapsed - show down caret
          icon.className = "ti ti-caret-down";
        } else {
          // Expanded - show up caret
          icon.className = "ti ti-caret-up";
        }
      }
    });
  }

  extractFormData(form) {
    const data = {};

    // For name field, check if the "other_name" text field is visible (meaning "other" was selected)
    const selectElement = form.querySelector("select[name*='[name]']");
    const otherNameField = form.querySelector("input[id*='other_name']");

    if (otherNameField && !otherNameField.hidden) {
      data["name"] = otherNameField.value;
      data["isOtherName"] = true;
    } else if (selectElement) {
      data["name"] = selectElement.value;
      data["isOtherName"] = false;
    }

    // Use scoped selectors for other fields
    const fieldMappings = {
      "input[type='date'][name*='[start_date]']": "start_date",
      "input[type='date'][name*='[end_date]']": "end_date",
      "select[name*='[fee_type]']": "fee_type",
      "input[name*='[entry_type]']": "entry_type",
      "input[name*='[parent_type]']": "parent_type",
      "input[name*='[parent_ids]']": "parent_ids",
      "input[name*='audit_name']": "audit_name",
      "input[type='checkbox'][name*='[cumulative]']": "cumulative",
      "input[type='checkbox'][name*='[formula]']": "formula",
      "input[name*='[notes]']": "notes",
    };

    Object.entries(fieldMappings).forEach(([selector, key]) => {
      const element = form.querySelector(selector);
      if (element) {
        if (element.type === "checkbox") {
          data[key] = element.checked;
        } else {
          data[key] = element.value;
        }
      }
    });

    return data;
  }

  populateFormData(form, data) {
    // Handle name field
    const selectElement = form.querySelector("select[name*='[name]']");
    const otherNameField = form.querySelector("input[id*='other_name']");

    if (data["name"]) {
      if (data["isOtherName"]) {
        // Source had "other" selected - copy the custom text value
        if (otherNameField) {
          otherNameField.value = data["name"];
        }
        if (selectElement) {
          selectElement.value = "Other";
          selectElement.dispatchEvent(new Event("change", { bubbles: true }));
        }
      } else {
        // Source had a regular option selected - just copy that option value
        if (selectElement) {
          selectElement.value = data["name"];
          selectElement.dispatchEvent(new Event("change", { bubbles: true }));
        }
      }
    }

    // Handle other fields
    const fieldMappings = {
      "input[type='date'][name*='[start_date]']": "start_date",
      "input[type='date'][name*='[end_date]']": "end_date",
      "select[name*='[fee_type]']": "fee_type",
      "input[name*='[entry_type]']": "entry_type",
      "input[name*='[parent_type]']": "parent_type",
      "input[name*='[parent_ids]']": "parent_ids",
      "input[name*='[audit_name]']": "audit_name",
      "input[type='checkbox'][name*='[cumulative]']": "cumulative",
      "input[type='checkbox'][name*='[formula]']": "formula",
      "input[name*='[notes]']": "notes",
    };

    Object.entries(fieldMappings).forEach(([selector, key]) => {
      const element = form.querySelector(selector);
      if (element && data[key] !== undefined) {
        if (element.type === "checkbox") {
          element.checked = data[key];
        } else {
          element.value = data[key];
        }

        // Trigger change event for any dependent logic
        element.dispatchEvent(new Event("change", { bubbles: true }));
      }
    });
  }
}
