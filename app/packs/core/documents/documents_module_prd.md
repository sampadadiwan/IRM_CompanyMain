# Product Requirements Document: Documents Module

## Overview

The Documents Module is a core component of the project, designed to provide robust capabilities for the storage, retrieval, and viewing of various documents. Its primary role is to centralize document management, ensuring that documents can be associated with multiple models within the application (e.g., users, funds, investments). Each document will be organized within a specific folder and linked to an owner. A critical aspect of this module is its sophisticated access control system, which combines explicit access rights for individual documents with implicit access rights derived from the document owner's visibility.

## Objectives

1.  **Centralized Document Management:** Establish a single, reliable system for storing and managing all types of documents across the application.
2.  **Flexible Document Association:** Enable seamless association of documents with various application models, allowing for a comprehensive view of related information.
3.  **Granular Access Control:** Implement a secure access rights mechanism that supports both explicit permissions for specific documents and implicit permissions based on the visibility of the document's owner.
4.  **Efficient Document Retrieval:** Provide fast and accurate methods for retrieving documents based on various criteria, including associated model, folder, owner, and access rights.
5.  **User-Friendly Viewing:** Offer an intuitive interface for users to view documents, ensuring a smooth and accessible experience.
6.  **Scalability and Performance:** Design the module to handle a growing volume of documents and concurrent user access without compromising performance.

## Features and Functionality

### Document Storage
*   **Upload Mechanism:** Support for uploading various document types (e.g., PDF, DOCX, images, video, excel) via a user interface using Active Storage.
*   **Metadata Capture:** Ability to capture and store essential metadata for each document (e.g., filename, size, upload date, uploader, document type, extension).
*   **Folder Organization:** Documents must be assigned to a specific folder upon upload. Folders can be created and managed. Documents inherit properties like `printing`, `download`, `original` from their associated folder.
*   **Owner Association:** Each document must be associated with an "owner" model (e.g., User, Fund, Investor KYC) via polymorphic association. The `MODELS_WITH_DOCS` constant defines the supported owner types: `Fund`, `CapitalCommitment`, `CapitalCall`, `CapitalRemittance`, `CapitalRemittancePayment`, `CapitalDitribution`, `CapitalDitributionPayment`, `Deal`, `DealInvestor`, `InvestmentOpportunity`, `ExpressionOfInterest`.

### Document Retrieval and Search
*   **Search and Filter:** Users can search for documents by filename, metadata, associated model, owner, folder, and tags. Advanced search capabilities are provided via Ransack for fields like `capital_call_id` and `commitments_fund_id`.
*   **Categorized Browsing:** Ability to browse documents by their associated model or folder structure.
*   **Elasticsearch Integration:** Utilizes Chewy for efficient full-text search and indexing of document metadata, including `name`, `folder_name`, `folder_full_path`, `entity_name`, `tag_list`, and `properties`.
*   **API Endpoints:** Provide secure API endpoints for programmatic retrieval of documents based on various parameters.

### Document Viewing and Tracking
*   **In-App Viewer:** Integrate a viewer for common document types (e.g., PDF, images, video, excel) directly within the application.
*   **Download Option:** Users can download documents to their local machine.
*   **Document Tracking:** Records `ViewedBy` entries to track which users have viewed specific documents.
*   **Version Control (Future Consideration):** Ability to manage multiple versions of a document (initially out of scope, but consider future extensibility).

### E-Signature Workflow
*   **Template-Based E-signing:** Documents can be marked as templates and configured with placeholder e-signatures. When a document is generated from a template, actual e-signatures are created based on data from the associated owner model (e.g., `investor_signatories`, `fund_signatories`).
*   **E-Signature Management:** Manage multiple e-signatures per document, each with its own status (requested, signed, failed, cancelled, voided, expired, sent).
*   **E-Signature Status Updates:** System handles callbacks from e-signing providers to update the status of e-signatures and the document.
*   **New Signed Document Creation:** Upon successful completion of e-signing, a *new*, locked "Signed" document is created, preserving the original template-generated document.
*   **Resend for E-sign:** Ability to resend documents for e-signing if the previous attempt failed, was cancelled, voided, or expired.
*   **E-sign Logging:** `EsignLog` records e-signing events.

### Document Questions (LLM Integration)
*   **Question Association:** Documents can have associated `DocQuestion` records, which are polymorphic and linked to an owner.
*   **Question Types:** Supports "Validation", "Extraction", and "General" question types.
*   **Dynamic Questioning:** Questions can be associated with documents by name or tags, enabling LLM-driven validation or data extraction from document content.

### Stamp Paper Management
*   **Stamp Paper Association:** Documents can be associated with `StampPaper` records, which are polymorphic and linked to an owner.
*   **Tag-Based Validation:** `StampPaper` records include tag validation to ensure proper format and adherence to entity-specific stamp paper tags.

### Access Rights Management
*   **Explicit Access Rights:**
    *   Define specific users or roles that have explicit view, edit, or delete permissions for a given document via `AccessRight` records.
    *   Mechanism to assign and revoke explicit access rights per document.
*   **Implicit Access Rights:**
    *   If a user has access to view the "owner" of a document (e.g., a specific user profile, a fund record), they implicitly gain view access to all documents associated with that owner, unless explicitly restricted.
    *   The system dynamically evaluates implicit access based on the current user's permissions on the owner model, leveraging `DocumentScope` and `InvestorsGrantedAccess` (if applicable).
    *   Access rights from the document's `Folder` are automatically copied to the document upon creation.
*   **Access Hierarchy:** Explicit access rights should override implicit access rights where there is a conflict (e.g., if implicit access is granted but explicit access denies, explicit denial takes precedence).
*   **Audit Trail:** Log all changes to document access rights for compliance and auditing purposes.

## User Stories and Use Cases

### User Stories
*   As an **Administrator**, I want to upload a new compliance document and associate it with the "Legal" folder and the "Company" owner, so that all legal team members can access it.
*   As an **Investor**, I want to view all documents related to my investment portfolio, so I can track my statements and reports.
*   As a **Fund Manager**, I want to upload a new fund prospectus and set explicit access rights for specific investors, so that only authorized individuals can view it.
*   As a **Support Agent**, I want to search for documents associated with a specific user by their name, so I can quickly find relevant information to assist them.
*   As a **System User**, I want to view a document associated with a fund, and because I have access to the fund details, I should automatically have access to view its associated documents.

### Use Cases
1.  **Uploading a New Document:**
    *   User navigates to the document upload section.
    *   User selects a file from their local machine.
    *   User specifies the document's folder and associated owner (e.g., a specific `Fund` instance).
    *   User optionally sets explicit access rights for other users/roles.
    *   System stores the document and its metadata, applying access rules.
2.  **Viewing an Investment Statement:**
    *   An Investor logs in and navigates to their investment portfolio.
    *   They click on a link to view their latest investment statement.
    *   The system checks if the Investor has explicit access to the statement OR if they have access to view their own `Investor` profile (the document's owner).
    *   If access is granted, the document is displayed in the in-app viewer.
3.  **Searching for a Compliance Document:**
    *   An Administrator searches for "AML Policy" in the document module.
    *   The system returns all documents matching the search query.
    *   The Administrator clicks on the relevant document.
    *   The system verifies explicit or implicit access rights before displaying the document.
4.  **Managing Document Access:**
    *   An Administrator selects a document and navigates to its access rights settings.
    *   They add a new user to the explicit access list for "view" permission.
    *   The system updates the document's access control list.

## Technical Requirements

*   **Programming Language/Framework:** Ruby on Rails (given `document.rb` in `app/packs/core/documents/models/`)
*   **Database:** PostgreSQL (common for Rails, assume for robust data storage).
    *   Tables for `documents`, `folders`, `access_rights`.
    *   Polymorphic associations for document owners (e.g., `documentable_type`, `documentable_id`).
*   **File Storage:**
    *   Cloud storage solution (e.g., AWS S3, Google Cloud Storage) for actual document files.
    *   Active Storage for Rails integration.
*   **Document Viewing:**
    *   Integration with a third-party document viewer library (e.g., PDF.js, WebViewer, or similar).
*   **Security:**
    *   Robust authentication and authorization mechanisms (e.g., Devise, Pundit).
    *   Data encryption at rest and in transit for sensitive documents.
    *   Input validation and sanitization to prevent vulnerabilities.
*   **APIs:** RESTful API design for document operations.
*   **Performance:** Implement caching strategies for frequently accessed documents and access rights.
*   **Logging and Monitoring:** Comprehensive logging for document access, modifications, and errors.