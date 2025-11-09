import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sectionsContainer", "template", "stepWizardRow"]

  connect() {
    this.element.querySelector('form').addEventListener('turbo:submit-start', (event) => {
      if (this.addingSection) {
        event.preventDefault();
      }
    });
  }

  addSection() {
    this.addingSection = true;
    const wizardController = this.application.getControllerForElementAndIdentifier(this.element, "wizard")
    const sectionFields = this.sectionsContainerTarget.querySelectorAll(".section-fields");
    const lastSection = sectionFields[sectionFields.length - 1];
    const lastSectionButtonContainer = lastSection.querySelector(".form-group");

    // Replace the "Save" button with a "Next" button on the previously last section
    lastSectionButtonContainer.innerHTML = '<button class="btn btn-outline-primary nextBtn btn-lg pull-right" type="button" data-action="click->wizard#validateSection">Next</button>';

    const newIndex = sectionFields.length;
    const newSectionHtml = this.templateTarget.innerHTML.replace(/INDEX/g, newIndex);
    this.sectionsContainerTarget.insertAdjacentHTML("beforeend", newSectionHtml);
    const newSection = this.sectionsContainerTarget.querySelector(`[name="sections[${newIndex}][name]"]`).closest('.setup-content');
    newSection.id = `step-${newIndex + 1}`;

    const newStep = `
      <div class="stepwizard-step">
        <a href="#step-${newIndex + 1}" type="button" class="btn disabled btn-outline-primary btn-outline-circle">${newIndex + 1}</a>
        <p>New Section</p>
      </div>
    `;
    this.stepWizardRowTarget.insertAdjacentHTML("beforeend", newStep);

    // Re-initialize the wizard to recognize the new step
    wizardController.initialize();

    // Programmatically click the "Next" button on the previous section to navigate to the new one.
    const nextButton = lastSection.querySelector(".nextBtn");
    if (nextButton) {
      nextButton.click();
    }

    this.addingSection = false;
  }
}