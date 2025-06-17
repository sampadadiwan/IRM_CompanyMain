# Document Viewer Feature

## Introduction
This document outlines the requirements for adding a document viewer feature to the existing Document model. This feature will allow users to share documents with external recipients via email, providing an encrypted, tamper-proof link. When the recipient clicks the link, the document's view count should be updated.

## Goals
- Enable sharing of documents with a list of email addresses (doc_viewers) through a new `DocShare` model.
- Generate secure, encrypted, and tamper-proof links for document viewing.
- Send email notifications to doc_viewers with the generated links.
- Track and update the view count for each `DocShare` entry when the link is accessed.

## Features
1.  **Create `DocShare` model:**
    - A new model `DocShare` should be created.
    - `DocShare` belongs to `Document`.
    - `DocShare` should have the following attributes:
        - `email` (string): The email address of the document viewer.
        - `email_sent` (boolean, default: false): Flag to indicate if the email with the link has been sent.
        - `viewed_at` (datetime): Timestamp when the document was first viewed via the link.
        - `view_count` (integer, default: 0): Number of times the document has been viewed via this specific link.
2.  **Update `Document` model:**
    - `Document` should `has_many :doc_shares`.
    - The `Document` model will no longer directly store `doc_viewer_emails` or `view_count`.
3.  **Encrypted Link Generation:**
    - Implement a mechanism to generate unique, encrypted, and time-limited links for each `DocShare` record.
    - The link must contain enough information to identify the `DocShare` record securely, without exposing sensitive data.
    - The link should be tamper-proof, meaning any modification to the URL parameters should invalidate it.
4.  **Email Notification:**
    - Create a new mailer to send emails to `doc_viewers` using the `DocShare` record.
    - The email should contain the encrypted link and a clear call to action.
    - The email content should be customizable and follow the same pattern as other existing Mailers in the application.
5.  **View Count Tracking:**
    - When an encrypted link is accessed, the system must verify its authenticity and validity against the `DocShare` record.
    - Upon successful validation, the `view_count` for the corresponding `DocShare` record should be incremented.
    - The `viewed_at` timestamp should be updated on the first view.
6.  **Security Considerations:**
    - Ensure that only authorized `doc_viewers` can access the document via the link.
    - Implement measures to prevent brute-force attacks on links.
    - Consider link expiration or single-use options.

## Technical Details
- **Model Changes:**
    - Create `DocShare` model with `email`, `email_sent`, `viewed_at`, `view_count`, and `document_id`.
    - Add `has_many :doc_shares` to `Document`.
- **Link Encryption:**
    - Utilize Rails' `ActiveSupport::MessageVerifier` or similar secure token generation for link encryption, specifically for `DocShare` records.
- **Mailer:**
    - Create a new Rails Mailer (e.g., `DocShareMailer`).
    - Define a method for sending the encrypted link, taking a `DocShare` object as input.
    - Ensure the mailer adheres to existing mailer patterns (e.g., `DocumentNotifier`).
- **Controller/Route:**
    - Define a new route (e.g., `/doc_shares/:token/view`) that handles the encrypted link.
    - Implement a controller action to:
        - Validate the token and find the `DocShare` record.
        - Increment `doc_share.view_count`.
        - Update `doc_share.viewed_at` if it's the first view.
        - Redirect to the document view (e.g., `/documents/:document_id/show`).
- **Policy Changes:**
    - Update `DocumentPolicy` to allow viewing of documents via the encrypted `DocShare` link, ensuring proper authorization.
- **Background Jobs:**
    - Consider using `Active Job` for sending emails to avoid blocking the main thread.

## Acceptance Criteria
- A user can specify a list of emails, which creates `DocShare` records for a document.
- Each `DocShare` record's email receives a unique, encrypted link.
- Clicking the link allows viewing of the document (if authorized via the `DocShare` record and `DocumentPolicy`).
- The `DocShare` record's `view_count` increments upon successful viewing via the link.
- The `DocShare` record's `viewed_at` is set on the first view.
- Invalid or tampered links are rejected.
- Email notifications follow existing application patterns.