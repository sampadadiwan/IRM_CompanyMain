# User Guide: Reset Access Rights Cache

## Overview
The Reset Access Rights Cache feature has been removed from CapHive: permissions are now checked live against access rights, approvals and roles on every page load, so there is no cache to reset.

> **Where to find it:** This feature has been removed — there is no **Reset Access Rights Cache** button on the user page any more, because CapHive now checks access live on every page load. To review access, use Company menu → [**User / Company Employees**](/users) for staff, and a fund's **Access** tab or a stakeholder's **Users** and **Access Rights** tabs for investors. See the FAQ below.

CapHive used to keep a stored copy of each user's permissions (the access rights cache) to speed up permission checks. That copy could fall out of step with the real access rights after complex changes, so administrators had a button to rebuild it. The cache, the button and its background job were all removed.

## Purpose
This page is kept so that older links and support notes still land somewhere useful. If you were sent here to "reset the cache" for a user, follow the checks below instead — any change you make to access takes effect the next time the user loads or reloads a page.

## Who Can Use This?
Nobody — the reset no longer exists for company admins or CapHive support. The access checks below can be done by:
- **Company Administrators**: users' roles, feature toggles and extended permissions, and employee access to stakeholders.
- **Anyone who can update the fund, document, folder or stakeholder**: granting and removing Access Rights and approving Stakeholder Users.

## How to Reset the Cache

There is nothing to reset. When a user sees too much or too little, check the live sources of access:

1.  **Investor cannot see a fund or document**:
    *   Open the stakeholder (Sidebar → **Stakeholders → View Stakeholders**) and check the person's row on the **Users** tab is **Approved**.
    *   Check the fund's **Access** tab (or the document's or folder's **Access Rights** tab) has a grant covering their stakeholder by name, category or tag. For documents in a shared folder, existing files are covered only if **Apply to files and sub folders** was ticked.
    *   On the fund, **Actions → Misc → Check Access Rights** lists commitments whose stakeholder has no fund grant.

2.  **Employee cannot see something**:
    *   Open Company menu → **User / Company Employees** → **Edit** on the user and check their feature toggles and extended permissions.
    *   Check the entity has the feature enabled (CapHive support switches entity features on).
    *   For employees who are not company admins, check they have an **Employee** grant on the fund or access on the stakeholder's **Access Rights → Employee Access** sub-tab.

3.  **Someone still sees something you removed**:
    *   Ask them to reload the page.
    *   Look for another grant that still covers them — a category or tag grant, a folder grant inherited by the document, or a second stakeholder they belong to.

## Technical Details
- The `access_rights_cache` columns on users, the `ResetAccessRightsCacheJob` background job and the reset action were removed.
- Permission checks and list scopes now query `AccessRight` and `InvestorAccess` records directly, so grants, removals, approvals and role changes are effective immediately.
- No completion notification exists any more, because there is no background rebuild.

## Frequently Asked Questions

### Navigation and getting there

**Where is the Reset Access Rights Cache button?**
It no longer exists. The access rights cache was removed from CapHive, so the user page has no **Reset Access Rights Cache** button and there is no background reset job or completion notification. [How to Reset the Cache](#how-to-reset-the-cache) lists the checks to use instead.

**Where do I check a user's access now?**
For staff: Company menu (the **house icon** at the top right, tooltip "Company menu") → [**User / Company Employees**](/users) → **Edit** on the user shows their roles, feature toggles and extended permissions. For investor logins: open the stakeholder from [**Stakeholders → View Stakeholders**](/investors) and check the **Users** and **Access Rights** tabs.

**Where do I check who can see a fund?**
Sidebar → [**Funds → Funds**](/funds) → open the fund → **Access** tab lists every grant. The fund's **Actions → Misc → Check Access Rights** reports commitments whose stakeholder has no grant, and **Show Email List** shows the details of every user with access to the fund.

**Where do I give an employee access to a specific stakeholder?**
Open the stakeholder → **Access Rights** tab → **Employee Access** sub-tab (company admins only) → **Grant Access**. See the [Investor Access guide](investor_access_tutorial).

### Creating, updating and managing access without a cache

**How do I refresh a user's access after changing their permissions?**
Nothing needs refreshing. Permission checks read access rights, Stakeholder User approvals and roles live from the database on every page, so a change applies the next time the user loads or reloads a page.

**How do I fix an investor who cannot see a fund or document?**
Check that their row on the stakeholder's **Users** tab is **Approved**, that the fund's **Access** tab (or the document's **Access Rights** tab) has a grant covering their stakeholder by name, category or tag, and that they were added under the right stakeholder. Once those are right they see the item on their next page load.

**How do I fix an employee who cannot see something?**
Check their feature toggles and extended permissions on their **Edit** page, that the entity has the feature enabled, and, for employees who are not company admins, that they have an **Employee** grant on the fund or access to the stakeholder. Company admins see everything in their entity.

**How do I remove someone's access immediately?**
Click **UnApprove** on their Stakeholder User row, or delete the grant on the fund's **Access** tab. The next page they load no longer shows the item; there is no cache that could keep it visible.

**Which permission do I need to change access?**
Editing users' roles and permissions needs the company admin role. Granting or removing access on a fund, document or folder needs permission to update that item, and approving Stakeholder Users needs permission to update the stakeholder.

### Why the cache was removed

**Why was the access rights cache removed?**
The cache stored a copy of each user's permissions that could fall out of step with the real access rights after complex changes such as stakeholder merges or advisor mappings, which is why a manual reset existed. Checking access live removes that failure mode, so there is nothing to reset.

**What does this mean for day-to-day administration?**
Every grant, removal, approval and role change is effective immediately for the affected users. You no longer need to ask support for a cache reset after merging stakeholders, changing an advisor's mapping or bulk-importing access.

**Who is affected by this change?**
Company admins and CapHive support, who were the only users able to reset the cache. Investors and employees are unaffected apart from seeing access changes straight away.

### What happens when I …

**What happens when I grant or remove an Access Right?**
Covered users can or cannot see the item on their next page load. Granting with **Send Notification** ticked emails them; removing access notifies no one.

**What happens when I approve or un-approve a Stakeholder User?**
The person gains or loses sight of everything shared with their stakeholder immediately and starts or stops receiving that stakeholder's notifications. Nobody is emailed about the change itself.

**What happens when two stakeholders are merged?**
Commitments, KYC, notes and Stakeholder Users move to the surviving stakeholder in a background job, and the users' access follows automatically once it finishes; no per-user reset is needed.

### Troubleshooting and edge cases

**A user still sees something I just removed.**
The page they are looking at was loaded before the change. Ask them to reload; if it still shows, check for another grant that covers them, such as a category or tag grant, a folder grant inherited by the document, or a second stakeholder they belong to.

**A user cannot see something I just shared.**
Ask them to reload the page. If it still does not appear, their Stakeholder User may be unapproved, the grant may target a different stakeholder or category, or (for documents) the grant may be on the parent folder without **Apply to files and sub folders** ticked for existing files.

**An old support note tells me to reset the access rights cache.**
That advice predates the cache's removal. Follow the checks in this FAQ instead; if access is still wrong after them, contact CapHive support with the user's email and the item they cannot see.

**An investor advisor sees the wrong client's data.**
Advisors see data for the client currently chosen in the persona dropdown in the top bar. Ask them to pick the right client, or **Self** for their own firm. See the [Investor Advisor guide](investor_advisor_user_guide).

## Related Guides

- [Investor Access & Permissions](investor_access_tutorial) — approvals and Access Rights, the live source of investor visibility.
- [User and Role Management](user_role_management_user_guide) — roles, feature toggles and extended permissions for staff.
- [Investor Advisor](investor_advisor_user_guide) — persona switching that changes what an advisor sees.
- [Investors (Stakeholders)](investors_user_guide) — merging stakeholders and the Access Rights tab.
- [Document Management](document_management_user_guide) — folder grants and inheritance.
