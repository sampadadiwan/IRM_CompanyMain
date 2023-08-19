import { Controller } from "@hotwired/stimulus"
const { Dashboard, GoogleDrive, Dropbox } = Uppy

import { uppyInstance, uploadedFileData } from 'custom/uppy'

export default class extends Controller {
  static targets = [ 'input' ]
  static values = { types: Array, server: String, dropHere: String, ownerTag: String, parentModel: String }
  file_count = 0

  connect() {
    this.uppy = this.createUppy();
    console.log(`Uppy created ${this.parentModelValue}`);
    console.log(this.uppy);
    if(this.ownerTagValue == 'Seller') {
      // Hack to avoid seller docs overwriting buyer docs
      this.file_count = 100;
    }
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
        height: 250,
        replaceTargetContent: true,
        locale: {
          strings: {
            dropPasteFiles : `Drop ${this.dropHereValue} or %{browseFiles}`,
          },
        },          
      })
      // .use(GoogleDrive, { target: Dashboard, companionUrl: 'https://companion.uppy.io' })
      // .use(Dropbox, { target: Dashboard, companionUrl: 'https://companion.uppy.io' })
      
    
    uppy.on('upload-success', (file, response) => {

      const hiddenField = document.createElement('input')
      hiddenField.type = 'hidden'
      this.file_count += 1
      hiddenField.name = `${this.parentModelValue}[documents_attributes][${this.file_count}][file]`
      hiddenField.value = uploadedFileData(file, response, this.serverValue)
      this.element.appendChild(hiddenField)

      const hiddenFieldName = document.createElement('input')
      hiddenFieldName.type = 'hidden'
      hiddenFieldName.name = `${this.parentModelValue}[documents_attributes][${this.file_count}][name]`
      hiddenFieldName.value = file.name
      this.element.appendChild(hiddenFieldName)

      const hiddenFieldOwnerTag = document.createElement('input')
      hiddenFieldOwnerTag.type = 'hidden'
      hiddenFieldOwnerTag.name = `${this.parentModelValue}[documents_attributes][${this.file_count}][owner_tag]`
      hiddenFieldOwnerTag.value = this.ownerTagValue
      this.element.appendChild(hiddenFieldOwnerTag)

    })

    return uppy
  }
};
