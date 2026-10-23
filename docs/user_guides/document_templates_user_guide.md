# Document Templates User Guide

A document template is a Word file you upload once so CapHive can fill it with each investor's data and produce their personalised agreement, notice or statement as a PDF.

> **Where to find it:** Sidebar → [**Funds → Funds**](/funds) → open the fund → **Actions → Misc → New Template** (the **Misc** menu is hidden on phone-sized screens). Choose what the template is for in **Document For**. Secondary sales use **Actions → New Template** on the sale page (Sidebar → [**Secondary Sales**](/secondary_sales)). Templates you added are listed on the fund's or sale's **Documents** tab. Needs update access on the fund or sale (company admins have it).

People call templates by many names: a **contribution agreement template**, **subscription agreement template** and **commitment agreement template** are all the same thing in CapHive, a fund template tagged **Commitment Template**. A **capital call notice** or **drawdown notice** template is a fund template tagged **Call Template**. "Doc gen" or **Generate Documents** is the step that fills the template.

---

## Table of Contents

1. [How Templates Work](#how-templates-work)
2. [Which Tag to Choose](#which-tag-to-choose)
3. [Adding a Fund Template](#adding-a-fund-template)
4. [The Template Form](#the-template-form)
5. [Naming Rules](#naming-rules)
6. [Finding, Replacing and Deleting a Template](#finding-replacing-and-deleting-a-template)
7. [Writing the Word File](#writing-the-word-file)
8. [Headers, Footers and Appended Documents](#headers-footers-and-appended-documents)
9. [A Different Template for One Commitment](#a-different-template-for-one-commitment)
10. [Generating Documents](#generating-documents)
11. [What Happens When Documents Are Generated](#what-happens-when-documents-are-generated)
12. [Secondary Sale Templates](#secondary-sale-templates)
13. [KYC Templates](#kyc-templates)
14. [Investment Opportunity Templates](#investment-opportunity-templates)
15. [Fixing a Broken Template](#fixing-a-broken-template)
16. [Frequently Asked Questions](#frequently-asked-questions)
17. [Related Guides](#related-guides)

---

## How Templates Work

1. You upload a Word document (`.docx`) to a fund (or a secondary sale) and set **Document For** to a tag such as **Commitment Template**.
2. The file contains placeholders ("merge fields") such as the investor's name, the committed amount or the call due date.
3. When someone clicks **Generate Documents** (or **Generate All Documents**) on a commitment, call, distribution or other record, CapHive finds every template with the matching tag, fills the placeholders with that record's data and converts the result to PDF.
4. The PDF is saved on the record's **Documents** tab as a generated, unapproved document. An approver approves it, and it can then be emailed or sent for e-signature.

The **Document For** tag is what connects a template to the right **Generate** button. A Word file uploaded without the tag is just a document; no generation step will pick it up.

---

## Which Tag to Choose

### Fund templates

The **Document For** list on a fund offers four tags:

| Document For | What it generates | Generated from |
|---|---|---|
| **Commitment Template** | The commitment agreement for each folio — also called the contribution agreement or subscription agreement. | A commitment's **Actions → Generate All Documents** / **Generate [template name]**, or the **Generate** dropdown on the fund's **Commitments** tab. |
| **Call Template** | The capital call notice (drawdown notice) for each remittance. | A call's or remittance's **Actions → Generate Documents**. |
| **Distribution Template** | The distribution notice for each distribution payment. | A distribution's or payment's **Actions → Generate Documents**. |
| **Investor Statement Template** | The investor statement (statement of account) for a period. | A commitment's **Actions → Generate Investor Statement**, or the statement option when allocating account entries. |

Older funds may still have templates tagged **SOA Template**; they keep working as investor statement templates, but the tag is no longer offered in the list. Use **Investor Statement Template** for new ones.

### Secondary sale templates

A secondary sale's **Document For** list offers **Offer Template** (the seller-side SPA, per offer), **Buyer Template** (the buyer-side document, per interest) and **Allocation Template** (the agreement per allocation). **Buyer** and **Seller** are also in the list but are ordinary party documents, not templates. See [Secondary Sale Templates](#secondary-sale-templates).

---

## Adding a Fund Template

1. Sidebar → [**Funds → Funds**](/funds) and open the fund.
2. Click **Actions → Misc → New Template**. (The tooltip reads "Add word templates for agreement, notices, statements".)
3. Enter a **Name** — it becomes part of every generated document's name, for example "Contribution Agreement".
4. Choose **Document For** (for example **Commitment Template**).
5. Upload the Word file.
6. Optionally tick **Template** to reveal the **eSignatures** section and add signatories (see below).
7. Click **Save**, or **Save & Upload More** to add another template with the same settings.

The template is saved in the fund's own folder and you are returned to the fund's **Documents** tab. Choosing a **Document For** tag containing "Template" marks the document as a template automatically, so it is hidden from investors browsing the fund's documents.

Use **Actions → Misc → New Template** rather than **New Document** on the **Documents** tab: the folder-based **New Document** form shows a **Folder** picker instead of **Document For**, so the file is saved without a tag and no **Generate** button will use it.

---

## The Template Form

| Field | What to do with it on a template |
|---|---|
| **Name** | Required. Becomes the start of each generated document's name and the label of **Generate [template name]**. |
| **Document For** | Required for generation. Picks which **Generate** action uses the template. |
| **Tags** | Optional searchable labels. |
| **As Of Date** | Leave blank; generated documents get their own date. |
| **Upload File** | The `.docx` template. |
| **Allow Original Format Download**, **Allow Download**, **Allow Printing**, **Embed Document** | Copied to every document generated from the template. |
| **Send email** | Leave unticked. On a fund template it emails everyone with access to the fund that a document was uploaded. |
| **Template** | Set automatically on save when **Document For** contains "Template". Tick it yourself to reveal the e-signature fields. |
| **Template: Docs to append** | Comma-separated names of KYC documents (for example a passport copy) to add at the end of each generated commitment agreement or KYC document. |
| **Description** | Free text for your team. |
| **eSignatures** (**Add Signature**) | Signer slots copied to each generated document. **Investor Signatories** uses the commitment's **Investor Signatory Emails**; **Fund Signatories** uses the fund's **Fund Signatory Emails**; any other label uses the email typed in **Notes**. **Esign display on page** and **eSign Order** are copied too. |
| **Add Stamp Paper** | Only when your e-sign provider is Digio. |

Generated documents are always converted to PDF. There is no user setting for the converter; if a template renders badly in PDF, use [Fixing a Broken Template](#fixing-a-broken-template) or contact CapHive support.

---

## Naming Rules

- Within one fund (or sale), two live templates cannot share the same **Name** and **Document For** tag. Saving a duplicate fails with "already exists as a template with this tag here. Edit that template (replace its file) or delete it before uploading another with the same name".
- Why: generation finds templates by tag and replaces earlier generated documents by template name, so two same-named templates would generate a document and then immediately delete it.
- The same name is allowed under a different tag, and a deleted template's name can be reused straight away.
- Extra spaces in a name are removed when you save.
- To update a template, replace its file (below) instead of uploading a second copy.

---

## Finding, Replacing and Deleting a Template

- **Find:** open the fund → **Documents** tab → the fund's folder. Templates are listed with their **Document For** tag. The commitments **Generate** dropdown also lists each **Commitment Template** by name.
- **Replace the Word file:** open the template, click **Edit**, upload the new file and **Save**. The name, tag and signatories stay, so every **Generate** button keeps working.
- **Change the tag or name:** same **Edit** form.
- **Delete:** open the template and click **Delete**. Documents already generated from it are not deleted. An allocation run template that used it as its statement document stops working until you choose another.

---

## Writing the Word File

Templates use Word **merge fields**. In Word choose **Insert → Quick Parts → Field → MergeField** and type the field name. Each field is shown as «…» in the document.

| You want | Field name to type | Example |
|---|---|---|
| Print a value | `=` + path | `=fund.name`, `=investor_kyc.full_name`, `=investor_kyc.address` |
| Print money with currency | `money_` before the attribute | `=capital_commitment.money_committed_amount`, `=capital_remittance.money_call_amount` |
| Print a date as "19 August 2026" | `date_format_` before the attribute | `=capital_commitment.date_format_commitment_date`, `=capital_call.date_format_due_date` |
| Print a number with commas | `format_` (2 decimals), `format_0_` / `format_nd_` (no decimals) | `=capital_remittance.format_call_amount` |
| Amount in words | `rupees_` / `indian_words_` (Indian style), `dollars_` | `=capital_commitment.rupees_committed_amount` |
| A custom field | `custom_fields.` + field name | `=investor_kyc.custom_fields.constitution` |
| Repeat a block per row | `list:each(item)` … `list:endEach` | `capital_remittances:each(remittance)` … `=remittance.money_collected_amount` … `capital_remittances:endEach` |
| Show a block only sometimes | `…:if` … `…:endIf` | `investor_kyc.custom_fields.compare_mode_of_holding_eq_Joint:if` … `investor_kyc.custom_fields.compare_mode_of_holding_eq_Joint:endIf` |
| Insert an image | `@name:start` and `@name:end` around a placeholder picture | `@investor_signature:start` … `@investor_signature:end` |

Other helpers work the same way: `sum_` / `sum_amt_` total a column over a list, `where_<field>_eq_<value>` filters a list, `list_` joins a list of values with semicolons, `div_N_` / `mult_N_` divide or multiply a number by 10^N (`=capital_commitment.div_7_committed_amount` shows crores; `=kpi.mult_2_q1_fy25` shows a stored 0.12 as 12), `boolean_custom_field_<name>` turns a Yes/No custom field into a condition, and `compare_<field>_eq_` / `_noteq_` / `_gt_` / `_lt_` build conditions.

### Which data each template can use

| Template | Top-level names you can start a field with |
|---|---|
| Commitment Template | `fund`, `capital_commitment`, `investor_kyc`, `fund_unit_setting`, `capital_remittances` (verified), `entity`, `date`; images `investor_signature`, `profile_image`, `profile_image_2` |
| Call Template | `fund`, `capital_call`, `capital_remittance`, `capital_commitment`, `investor_kyc`, `fund_unit_setting`, `entity`, `date`, `due_date`, `call_date`, plus fund-wide lists such as `fund_as_of_commitments` and `fund_as_of_remittances` as of the remittance date |
| Distribution Template | `fund`, `capital_distribution`, `capital_distribution_payment`, `capital_commitment`, `investor_kyc`, `fund_unit_setting`, `entity`, `date`, plus fund-wide lists as of the payment date |
| Investor Statement Template | `fund`, `capital_commitment`, `investor_kyc`, `start_date`, `end_date`, `format_start_date`, `format_end_date`, and period lists such as `capital_remittances_between_dates`, `capital_distribution_payments_before_end_date`, `commitment_adjustments_between_dates` |
| Offer Template | `offer`, `allocations`, `secondary_sale`, `sale_entity`, `offer_custom_fields`, `effective_date`, `current_date`; image `offer_signature` |
| Buyer Template | `interest`, `offers`, `secondary_sale`, `sale_entity`, `interest_custom_fields`, `effective_date`, `current_date`; image `interest_signature` |
| Allocation Template | `allocation`, `offer`, `interest`, `secondary_sale`, `sale_entity`, `allocation_custom_fields`, `effective_date`, `current_date`; images `offer_signature`, `interest_signature` |

### Listing every available field

There is no screen that lists the fields. To see them, put this loop in a test template, generate one document and read the list it prints: `context.all_keys:each(key)`, then `=key`, then `context.all_keys:endEach`. Remove the loop before using the template for real.

---

## Headers, Footers and Appended Documents

For commitment agreements (and KYC documents), CapHive adds extra PDF pages from documents on the commitment (or KYC) with these exact names:

- Before the agreement: **Header**, **Stamp Paper**, **[template name] Header**, **[template name] Stamp Paper**.
- After the agreement: **Footer**, **[template name] Footer**, **[template name] Signature**.
- After that, the KYC documents listed in the template's **Template: Docs to append**, in that order.

When you upload a document on a commitment, the **Name** list already offers "[template name] Header" and "[template name] Footer" for each fund template.

---

## A Different Template for One Commitment

To give one folio its own version of a fund template (for example a side-letter variant of the contribution agreement):

1. Open the commitment → **Documents** tab and add a new document.
2. Pick the same **Name** as the fund template from the **Name** list.
3. Tick **Template**, upload the variant Word file and save.

For that folio, generation (commitment agreements, investor statements, call notices and distribution notices) uses the commitment's template instead of the fund's one with the same name. The fund-wide **Generate** dropdown on the **Commitments** tab always uses the fund template you pick.

---

## Generating Documents

| Document | For one record | For many |
|---|---|---|
| Commitment agreement | Commitment → **Actions → Generate All Documents** or **Generate [template name]** | Fund → **Commitments** tab → **Generate** → the template's name (every folio in the fund) |
| Investor statement | Commitment → **Actions → Generate Investor Statement** → pick **Template name**, **Start date**, **End date** and **For** | Fund → **Commitments** tab → **Generate → Generate Investor Statement**, tick **Generate Investor Statements** on the allocation screen |
| Call notice | Remittance → **Actions → Generate Documents** | Call → **Actions → Generate Documents** (unapproved calls only) |
| Distribution notice | Distribution payment → **Actions → Generate Documents** | Distribution → **Actions → Generate Documents** |
| SPA / sale documents | Offer, interest or allocation → **Generate Document** → **All Docs** or a template | **All Allocations** → **Bulk Actions → Generate All Docs** |
| KYC documents | KYC → **KYC Actions → Generate Docs** | [**Funds → KYCs**](/investor_kycs), filter, **KYC Documents → Generate KYC Docs** |

Commitment agreement and investor statement actions appear only when the folio's KYC is verified; **Generate All Documents** also disappears once e-signing of the commitment is complete.

---

## What Happens When Documents Are Generated

- **Runs in the background.** You see "Documentation generation started, please check back in a few mins." and in-app alerts as each document is made ("Document [template] generated for [investor]. Please refresh the page."), then a final count.
- **One document per record per template.** Each template with the matching tag produces its own PDF.
- **Name.** The template name plus the record, for example "Contribution Agreement - Jane Doe - F001" or "Drawdown Notice - Jane Doe - F001". Investor statements add the period ("… 01 January,2026 to 31 March,2026 - …").
- **Where it is saved.** On the record's **Documents** tab: the commitment (statements go in its **Investor Statements** folder), the remittance, the distribution payment, the offer / interest / allocation, or the KYC.
- **Earlier copies.** A new document replaces the earlier generated document with the same name; signed copies are kept. For commitment agreements and investor statements, if a signed or approved copy with that name already exists the folio is skipped with "Signed document already exists…" or "Approved document already exists…".
- **Approval.** Every generated document starts unapproved, is invisible to investors and cannot be emailed or e-signed until a user with the **approver** role approves it.
- **E-signature.** Signer slots from the template are copied onto the document; nothing is sent until someone uses **Send For eSignatures**.
- **Who is notified.** Only the user who started it, by in-app alerts. If anything failed you also get an error email listing each failure. Investors receive nothing at this stage.
- **Skipped records.** KYC not verified, a commitment with `skip_doc_gen` set to Yes (call and distribution notices), an offer that is not approved, an interest that is not shortlisted or an allocation that is not verified.

---

## Secondary Sale Templates

1. Sidebar → [**Secondary Sales**](/secondary_sales) and open the sale.
2. **Actions → New Template**.
3. Choose **Document For**: **Offer Template**, **Buyer Template** or **Allocation Template**, upload the Word file and save. Signatory labels offered are **Buyer Signatories**, **Seller Signatories** and **Other**.

Generate from an approved offer, a shortlisted interest or a verified allocation (**Generate Document**), or for many allocations with **Bulk Actions → Generate All Docs**. An allocation or offer whose `docs_to_generate` custom field lists template names only generates those templates. See the [Secondary Sales guide](secondary_sales_user_guide).

---

## KYC Templates

KYC documents (for example an investor declaration form) use templates stored in a folder named exactly **KYC Templates**:

1. Sidebar → [**Documents**](/documents), select the top folder and choose **Actions → New Folder**; name it **KYC Templates**.
2. Select that folder, choose **Actions → New Document**, upload the Word file, tick **Template** and save.
3. Generate with **KYC Actions → Generate Docs** on a KYC (pick start date, end date and one or more templates, then **Generate Now**), or for many KYCs filter [**Funds → KYCs**](/investor_kycs) and use **KYC Documents → Generate KYC Docs**.

Only verified KYCs get documents, and only templates placed directly in that folder are offered.

---

## Investment Opportunity Templates

An investment opportunity's **Document For** list has **Template** and **Document**, intended for expression-of-interest documents. **Generate Documents** is currently not offered on expressions of interest, so no documents are produced from an opportunity template today.

---

## Fixing a Broken Template

If generated documents have duplicated or skipped clause numbers, unexpected blank space, or a section that shows for every investor when it should not, a company administrator can open the template and click **Fix Me**. The [Template Fix Agent](agents/template_fix_agent_user_guide) returns a corrected draft to review; the original template is never changed until you replace its file yourself.

---

## Frequently Asked Questions

### Navigation and getting there

**Where do I add a document template in CapHive?**
Open the fund (Sidebar → [**Funds → Funds**](/funds)) and choose **Actions → Misc → New Template**. For a secondary sale open the sale and use **Actions → New Template**. KYC templates go in a **KYC Templates** folder under Sidebar → [**Documents**](/documents). See [Adding a Fund Template](#adding-a-fund-template).

**Where do I see the templates a fund already has?**
Open the fund and click its **Documents** tab, then the fund's folder; templates are listed with their **Document For** tag. The **Generate** dropdown on the fund's **Commitments** tab also lists every **Commitment Template** by name. Investors never see templates in the fund's documents.

**Why don't I see New Template in the fund's Actions menu?**
It is under **Actions → Misc**, which needs update access on the fund (company admins have it). The **Misc** menu is hidden on phone-sized screens, so use a wider window. If you still don't see it, ask your company administrator for update rights on the fund.

**Why is there no Document For field when I upload a Word template?**
You used **New Document** on a folder, which shows a **Folder** picker instead of **Document For**, so the file gets no tag and generation ignores it. Delete it and add the file again with the fund's **Actions → Misc → New Template** (or **Actions → New Template** on a secondary sale), where **Document For** is shown.

**Is there a list of all merge fields I can use in a Word template?**
No screen lists them. The [Writing the Word File](#writing-the-word-file) section lists the top-level names per template. To see every field, add the loop `context.all_keys:each(key)`, `=key`, `context.all_keys:endEach` to a test template, generate one document and read the printed list, then remove the loop.

### Creating, updating and managing templates

**How do I add a contribution (commitment agreement) template for capital commitments?**
A contribution agreement template is a commitment agreement template. Open the fund → **Actions → Misc → New Template**, name it (for example "Contribution Agreement"), set **Document For** to **Commitment Template**, upload the Word file with merge fields and save. Generate it from a commitment's **Actions → Generate All Documents** or for all folios from the **Generate** dropdown on the **Commitments** tab.

**How do I add a subscription agreement template?**
In CapHive a subscription agreement is the commitment agreement. Open the fund → **Actions → Misc → New Template**, set **Document For** to **Commitment Template**, upload the Word file and save. It then appears as **Generate [template name]** on each commitment's **Actions** menu and in the **Generate** dropdown on the fund's **Commitments** tab.

**How do I add a template for any document CapHive generates?**
Pick the place and tag that match the document: fund **Actions → Misc → New Template** with **Commitment Template** (commitment, contribution or subscription agreement), **Call Template** (capital call notice), **Distribution Template** (distribution notice) or **Investor Statement Template**; a sale's **Actions → New Template** with **Offer**, **Buyer** or **Allocation Template**; or the **KYC Templates** folder for KYC documents. See [Which Tag to Choose](#which-tag-to-choose).

**How do I add a capital call notice template?**
Open the fund → **Actions → Misc → New Template**, name it (for example "Drawdown Notice"), set **Document For** to **Call Template**, upload the Word file and save. Fields such as `=capital_remittance.money_call_amount` and `=capital_call.date_format_due_date` fill in per investor. Generate from the call's **Actions → Generate Documents**.

**How do I add a distribution notice template?**
Open the fund → **Actions → Misc → New Template**, set **Document For** to **Distribution Template**, upload the Word file and save. Fields such as `=capital_distribution_payment.money_net_payable` fill in per payment. Generate from the distribution's **Actions → Generate Documents** (every payment) or a payment's **Actions → Generate Documents**.

**How do I add an investor statement template?**
Open the fund → **Actions → Misc → New Template**, set **Document For** to **Investor Statement Template**, upload the Word file and save. Use fields such as `=format_start_date`, `=format_end_date` and lists like `capital_remittances_between_dates`. Generate with a commitment's **Actions → Generate Investor Statement**, choosing the template, dates and **For**.

**What is the difference between Document For and Tags on a template?**
**Document For** decides which generation step uses the template (for example **Call Template** for call notices) and is required for a template to work. **Tags** are free search labels with no effect on generation. A Word file with the right tags but no **Document For** value is never used.

**How do I write merge fields in a Word template?**
In Word choose **Insert → Quick Parts → Field → MergeField** and type the field name, starting with `=` to print a value, for example `=investor_kyc.full_name` or `=capital_commitment.money_committed_amount`. Repeat blocks with `name:each(item)` … `name:endEach` and show blocks conditionally with `…:if` … `…:endIf`. See [Writing the Word File](#writing-the-word-file).

**How do I format amounts and dates in a template?**
Put a helper before the attribute name: `money_` prints the amount with currency, `date_format_` prints a date like "19 August 2026", `format_` adds commas with 2 decimals (`format_0_` for none), and `rupees_` or `dollars_` spell the amount in words. Example: `=capital_call.date_format_due_date`.

**How do I use custom fields in a Word template?**
Add `custom_fields.` and the custom field's name after the record, for example `=investor_kyc.custom_fields.constitution` or `=investor_kyc.custom_fields.client_email_id`. For a Yes/No custom field in a condition use the record plus `boolean_custom_field_<name>:if` … `:endIf`, for example on `capital_commitment`.

**How do I add signatures to documents generated from a template?**
Edit the template, make sure **Template** is ticked and use **Add Signature**. Label **Investor Signatories** to use the commitment's **Investor Signatory Emails**, **Fund Signatories** for the fund's **Fund Signatory Emails**, or any other label with the signer's email in **Notes**. Each generated document copies these slots; see the [E-Signing guide](esigning_user_guide).

**How do I replace or update a template's Word file?**
Open the template from the fund's **Documents** tab, click **Edit**, upload the new file under **Upload File** and **Save**. Keep the same name and **Document For** so the **Generate** buttons and signatories keep working. Don't upload a second template with the same name and tag; that is rejected.

**How do I delete a document template?**
Open the template from the fund's or sale's **Documents** tab and click **Delete**. Documents already generated from it stay on their records. If an allocation run template used it as its statement document, pick another one there before the next run.

**Can a fund have more than one commitment agreement template?**
Yes. Give each a different name and the tag **Commitment Template**, for example one for individuals and one for entities. **Generate All Documents** builds one document from each; use **Generate [template name]** on the commitment, or the template's entry in the **Generate** dropdown, to generate only one.

**How do I use a different template for one investor's commitment?**
Open the commitment → **Documents** tab, add a document, choose the fund template's name from the **Name** list, tick **Template**, upload the variant Word file and save. That folio's commitment agreement, statements and notices then use its own template instead of the fund's one with that name. See [A Different Template for One Commitment](#a-different-template-for-one-commitment).

**How do I add a header, footer or stamp paper to a generated commitment agreement?**
Upload a PDF or image to the commitment named "[template name] Header", "[template name] Stamp Paper", "[template name] Footer" or "[template name] Signature" (or just "Header" / "Footer"). They are added before or after the agreement pages. KYC documents named in the template's **Template: Docs to append** are added at the end.

**How do I add a secondary sale SPA or allocation template?**
Open the sale → **Actions → New Template**, set **Document For** to **Offer Template** (seller SPA), **Buyer Template** (buyer document) or **Allocation Template**, upload the Word file and save. Generate from an offer, interest or allocation's **Generate Document** menu. See [Secondary Sale Templates](#secondary-sale-templates).

**How do I set up KYC form templates for generating KYC documents?**
Create a folder named exactly **KYC Templates** under the top folder in Sidebar → [**Documents**](/documents), then **Actions → New Document** in that folder, upload the Word file and tick **Template**. Generate with **KYC Actions → Generate Docs** on a verified KYC. See [KYC Templates](#kyc-templates).

### Why use document templates

**Why use document templates instead of writing each agreement or notice by hand?**
One Word file produces a personalised, correctly calculated document for every investor in minutes, with the same wording each time. Amounts, dates and KYC details come straight from CapHive, so there are no copy-paste errors, and each document lands on the right record ready for approval, email and e-signature.

**Who usually sets up document templates?**
Fund operations or legal teams with update access on the fund. They upload the agreement, notice and statement templates once per fund; operations staff then click **Generate Documents** for each call, distribution or new commitment, and an approver reviews the results.

**What goes wrong if a template has no Document For tag?**
Nothing is generated from it. The **Generate** actions look only for templates with the matching tag, so you get the alert "No templates found" or the template is simply missing from the **Generate** menus. Edit the document and set **Document For**.

### What happens when I …

**What happens when I generate documents from a template (doc gen)?**
A background job fills each matching template for each record and saves a PDF on the record's **Documents** tab, named after the template and the investor. The document starts unapproved and hidden from investors. You get in-app progress alerts and, if anything failed, an error email; investors are not notified. See [What Happens When Documents Are Generated](#what-happens-when-documents-are-generated).

**What happens when I click Generate All Documents on a commitment?**
Every **Commitment Template** (or the commitment's own template of the same name) is filled with the fund, commitment and KYC data and saved as a PDF on the commitment's **Documents** tab. An earlier unsigned generated copy with the same name is replaced; if a signed or approved copy exists that template is skipped with an alert.

**What happens when I pick a template in the Generate dropdown on the Commitments tab?**
That one **Commitment Template** is generated for every commitment in the fund. Folios without a verified KYC are skipped and listed in the error email. Each document goes to its commitment's **Documents** tab, unapproved.

**What happens when I generate call notices from the Call Template?**
One notice per remittance is built from each **Call Template** and saved unapproved on the remittance's **Documents** tab, replacing the earlier generated notice of the same name (a signed copy is kept). Remittances with an unverified KYC or `skip_doc_gen` set to Yes are skipped. Only approved notices are attached to the call email.

**What happens when I approve a generated document?**
It becomes visible to investors who have access to the record, can be attached to notification emails, and can be sent for e-signature. Approving needs the **approver** role. An approver can click **UnApprove** on the document if a commitment agreement or statement that is already approved needs to be regenerated.

**What happens to generated documents when I replace or delete the template?**
Nothing. Existing generated documents stay as they are; only documents generated afterwards use the new file. To refresh them, generate again (for commitment agreements and statements, unapprove or delete an approved copy first).

**What happens when I tick Send email on a template?**
Everyone with access to the document and, for a fund template, everyone with access to the fund is emailed that a document was uploaded. This is rarely wanted for a template, so leave **Send email** unticked.

**Does generating documents send anything to investors?**
No. Generation only creates unapproved documents. Investors receive documents when you send the call or distribution notification, use **Send Document**, or send the document for e-signature, and only after it has been approved.

### Troubleshooting and edge cases

**Why do I get "already exists as a template with this tag here" when saving a template?**
The fund (or sale) already has a live template with the same **Name** and **Document For** tag. Open that template and replace its file with **Edit**, or delete it first and then upload the new one. Using a different name also works, but both templates will then be generated.

**Why does generation say "No templates found"?**
No template with the needed tag exists on the fund or sale, for example no **Call Template** when generating call notices. Add one with **Actions → Misc → New Template** and the right **Document For**, or edit the existing document and set its tag.

**Why is my commitment agreement template not listed under Generate on the commitment?**
The template's **Document For** is not **Commitment Template**, or the commitment's KYC is not verified, or e-signing on the commitment is already complete; the generate items only show for a verified KYC and incomplete e-signing. Check the template's tag and verify the KYC.

**Why was a folio skipped with "is not verified" or "KYC not verified"?**
Documents are only generated for folios whose investor KYC is verified. Open the KYC (Sidebar → [**Funds → KYCs**](/investor_kycs)), check it and click **Verify**, then generate again for that folio.

**Why does it say "Approved document already exists" or "Signed document already exists"?**
For commitment agreements and investor statements, CapHive will not overwrite a copy that has been approved or signed. Ask an approver to open the existing document and click **UnApprove** (or delete it if it is not signed), then generate again. Signed documents are always kept.

**Why do placeholders show as blank or «=…» text in the generated PDF?**
A field whose first name isn't available to that template type (for example `capital_call` in a commitment agreement) prints nothing, and «» characters typed by hand are printed as text because they are not real merge fields. Check the name against [Which data each template can use](#which-data-each-template-can-use) and insert fields with **Insert → Quick Parts → Field → MergeField**.

**Why did generation fail with "Error generating [template] for [investor]"?**
Word could not be filled or converted, usually a merge field naming something that doesn't exist, an `:each` or `:if` without its matching `:endEach` / `:endIf`, or a corrupt file. The error email shows the message per investor. Fix the field in Word and replace the file, or try **Fix Me** on the template.

**Why are clause numbers or blank gaps wrong in documents generated from my template?**
This is usually list numbering or section breaks in the Word file that the PDF conversion reads differently. A company administrator can open the template and click **Fix Me** to get a corrected draft; see the [Template Fix Agent](agents/template_fix_agent_user_guide). Replace the template's file once the draft looks right.

**Why doesn't my template appear in the Generate Investor Statement Template Name list?**
The list shows only templates tagged **Investor Statement Template** (or the older **SOA Template**). Edit the template and set **Document For** to **Investor Statement Template**.

**Why does Generate Document → All Docs on a buyer interest produce nothing?**
Generating all **Buyer Template** documents at once for an interest currently does not complete. Open **Generate Document** on the interest and pick each Buyer Template by name instead, which generates that template correctly.

**Can I generate documents from a template on an investment opportunity?**
Not at present. You can store a file with **Document For** set to **Template** on an opportunity, but **Generate Documents** is not offered on expressions of interest, so nothing is produced from it.

**Can I use a .doc, PDF or Google Docs file as a template?**
No. Templates must be Word `.docx` files with merge fields. Save an older `.doc` or a Google Doc as `.docx` in Word, add the merge fields and upload that. Generated documents are always produced as PDF.

**Can investors see our templates?**
No. Documents marked as templates are excluded when investors browse a fund's documents. Investors only see generated documents after they are approved and only on records they have access to.

---

## Related Guides

- [Capital Commitments](capital_commitments_user_guide) — generating commitment (contribution / subscription) agreements and investor statements.
- [Capital Calls](capital_calls_user_guide) — generating and approving capital call notices.
- [Capital Distributions](capital_distributions_user_guide) — generating and approving distribution notices.
- [Secondary Sales](secondary_sales_user_guide) — SPA, buyer and allocation documents.
- [Document Management](document_management_user_guide) — folders, approving generated documents and access rights.
- [E-Signing](esigning_user_guide) — sending approved generated documents for signature.
- [Investor KYC](investor_kyc_user_guide) — verifying KYCs so documents can be generated.
- [Template Fix Agent](agents/template_fix_agent_user_guide) — repairing a template that produces faulty documents.
