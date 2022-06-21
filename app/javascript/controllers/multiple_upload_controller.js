import { Controller } from "@hotwired/stimulus"
const { Dashboard, GoogleDrive, Dropbox } = Uppy
import { nanoid } from 'nanoid'

import { uppyInstance, uploadedFileData } from '../uppy'
// import { nanoid } from 'nanoid'

export default class extends Controller {
  static targets = [ 'input' ]
  static values = { types: Array, server: String }
  file_count = 0

  connect() {
    this.uppy = this.createUppy();
    console.log("Upply created");
    console.log(this.uppy);
  }

  disconnect() {
    this.uppy.close()
  }

  createUppy() {
    const uppy = uppyInstance({
        id: this.inputTarget.id,
        types: this.typesValue,
        server: this.serverValue,
      })
      .use(Dashboard, {
        target: this.inputTarget.parentNode,
        inline: true,
        height: 300,
        replaceTargetContent: true,
      })
      // .use(GoogleDrive, { target: Dashboard, companionUrl: 'https://companion.uppy.io' })
      // .use(Dropbox, { target: Dashboard, companionUrl: 'https://companion.uppy.io' })
      
    
    uppy.on('upload-success', (file, response) => {
      const hiddenField = document.createElement('input')
      hiddenField.type = 'hidden'
      this.file_count += 1
      hiddenField.name = `folder[documents_attributes][${this.file_count}][file]`
      hiddenField.value = uploadedFileData(file, response, this.serverValue)
      this.element.appendChild(hiddenField)

      const hiddenFieldName = document.createElement('input')
      hiddenFieldName.type = 'hidden'
      hiddenFieldName.name = `folder[documents_attributes][${this.file_count}][name]`
      hiddenFieldName.value = file.name
      this.element.appendChild(hiddenFieldName)
    })

    return uppy
  }
}
