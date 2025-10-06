import { Controller } from "@hotwired/stimulus"
import { uppyInstance, uploadedFileData } from 'custom/uppy'
const { FileInput } = Uppy
const { Informer } = Uppy
const { StatusBar } = Uppy
const { ThumbnailGenerator } = Uppy


export default class extends Controller {
  static targets = [ 'input', 'result', 'preview' ]
  static values = { types: Array, server: String }

  connect() {
    console.log("Uppy created");
    this.inputTarget.classList.add('d-none');
    this.previewTarget.classList.add('d-none');
    this.uppy = this.createUppy();
  }

  disconnect() {
    this.uppy.close()
  }

  createUppy() {

    console.log(`this.inputTarget.id = ${this.inputTarget.id}`);

    const uppy = uppyInstance({
        id: this.inputTarget.id,
        types: this.typesValue,
        server: this.serverValue,
      })
      .use(FileInput, {
        target: this.inputTarget.parentNode,
        locale: { strings: { chooseFiles: 'Choose file' } },
      })
      .use(Informer, {
        target: this.inputTarget.parentNode,
      })
      .use(StatusBar, {
        target: `.${this.inputTarget.id}_progress`,
        hideUploadButton: false,
        hideAfterFinish: false,
      })
      .use(ThumbnailGenerator, {
        thumbnailWidth: 600,
      })

    uppy.on('upload-success', (file, response) => {
      // set hidden field value to the uploaded file data so that it's submitted with the form as the attachment
      this.resultTarget.value = uploadedFileData(file, response, this.serverValue)
      console.log("Upload success", file, response);
      // Remove the required attribute from the input file field to allow the form to submit
      $(this.inputTarget).removeAttr('required');

      this.element.dispatchEvent(new CustomEvent("upload:complete", {
        bubbles: true,
        detail: {
          file: file.data // Not file.meta, not file.response, not just file
        }
      }));

      console.log(`Dispatched upload:complete event with file data`);
    })

    uppy.on('thumbnail:generated', (file, preview) => {
      this.previewTarget.src = preview
      console.log("Thumbnail generated", file, preview);
      this.previewTarget.classList.remove('d-none');
    })

    return uppy
  }
}
