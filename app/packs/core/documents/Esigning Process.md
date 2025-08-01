# Esigning Process

For esigning, we have **two providers**: **Digio** and **Docusign**. The client can choose between the two and inform the team, and the team will ensure that the specified provider is used for the client's account.

By default, **Digio** is used for all clients with the default Caphive account.

Clients can make their own Digio account and provide the following details to the team to use it:

- **Client ID**
- **Client Secret**
- **Cutover Date**: date when we start using the client's account
- The team will update these details in the entity settings using the admin login.

## Esigning Flows

There are **4 flows** in the esigning process:

1. **Sending for esign**
2. **Fetching updates manually by hitting the API**
3. **Webhook for updates**
4. **Cancelling esign**

---

## Digio Process

- **Sending for esign:**

  - We hit the esign API.
  - If we get a **success response**, we update the document:
    - `sent_for_esign` to **true**
    - `esign_status` to **requested**
    - `sent_for_esign_date` to **current time**
    - Schedule a job to fetch updates
  - If we get a **failure response**, we update the document:
    - `sent_for_esign` to **true**
    - `esign_status` to **failed**
    
  - **Note:**
    - We schedule a job to fetch updates after sending for esign because Digio does not provide a webhook for just sending for esign - only for signed or failed.
    - We dont have esigns on specific pages for digio - as Digio required the page as well as the coordinates on that page for esign. With `First`,`All` or `Last` the position is determined automatically with overlap handling on Digio end. This overlap handling is complex and we do not want to handle it.
    - The Aadhaar esigning option is only available for Digio atm so it doesn't show for other esign providers.
    - Esigning in order (one after the other) is not working with Digio. We have to send all the signatories at once.

- **Fetching updates:**

  - We hit the fetch updates API.
  - If we get a **success response**, we update the document's esignatures according to the status received (e.g., **requested** or **signed**).

- **Webhook for updates:**

  - We provide a webhook URL to Digio.
  - When the document is signed, Digio sends a POST request to the webhook URL.
  - Irrespective of what we do with the webhook, we send a **200** back to acknowledge the webhook.
  - Using the webhook, we update the document's esignatures according to the status received.

- **Post-update checks:**

  - After manual or webhook updates, we store the api response in the e_signatures for tracking.
  - We also check if all the signatories have signed the document.
  - If yes, we update the document's `esign_status` to **signed** and download the signed document from Digio.
  - This signed document is saved on the platform with the same name as the original document and the owner_tag **signed**.

- **Cancellation:**
  - We hit the cancel esign API.
  - If we get a **success response**, we update the document:
    - `esign_status` to **cancelled**
    - Update the document's esignatures to **cancelled**

---

## Docusign Process

- **Sending for esign:**

  - We hit the esign API.
  - If we get a **success response**, we update the document:
    - `sent_for_esign` to **true**
    - `esign_status` to **sent**
  - If we get a **failure response**, we update the document:
    - `sent_for_esign` to **true**
    - `esign_status` to **failed**

  - **Note:**
    - Sequencing is available for Docusign and is enabled by default via the checkbox in the document template - force esign order. If this is not checked, the signatories can sign in any order as they all receive the email at the same time.

- **Fetching updates:**

  - We hit the fetch updates API.
  - If we get a **success response**, we update the document's esignatures according to the status received (e.g., **sent** or **completed**).

- **Webhook for updates:**

  - We provide a webhook URL to Docusign.
  - When the document is signed, Docusign sends a POST request to the webhook URL.
  - Irrespective of what we do with the webhook, we send a **200** back to acknowledge the webhook.
  - Using the webhook, we update the document's esignatures according to the status received (status can be **sent** or **completed**).

- **Post-update checks:**

  - After manual or webhook updates, we store the api response in the e_signatures for tracking.
  - We also check if all the signatories have signed the document.
  - If yes, we update the document's `esign_status` to **signed** and download the signed document from Docusign.
  - This signed document is saved on the platform with the same name as the original document and the owner_tag **signed**.

- **Cancellation:**

  - With Docusign, the cancellation is basically voiding the envelope.
  - We hit the cancel esign API (we can also send the reason for voiding).
  - The envolope can also be voided by the receipient of the document/envolope.
  - If we get a **success response**, we update the document:
    - `esign_status` to **cancelled/voided**
    - Update the document's esignatures to **cancelled/voided**

---

## Excecption Cases

- **Updates:**

  - If the document has been deleted from the platform and we get a webhook for it, we still send a 200 response back
  - A document that has been sent for esign cannot be deleted from the UI but can be deleted from the console or through a document generation process.
  - The document generators have a check that doesn't generate document if the original has been sent for esign but recently some bug has allowed this deletion.
  - After a webhook, the code can also fail to fetch a document using the esign provider's id if it has been tampered with, either through the admin login or through the console which can lead to a document not being updated.

- **Cancellation:**

  - If a document's esigning has completed but the user has not refreshed the page the "Cancel Esign" button will still be visible which, if clicked, will send a cancel esign request to the provider.
  - In this case the provider will return an error as the document has already been signed and the status cannot be changed. This error is shown to the user
