# User Guide: Reset Access Rights Cache

## Overview
The Investor Relationship Management (IRM) system utilizes an `AccessRightsCache` to optimize permission checks across the platform. This cache stores a bitmask of permissions for each user based on their roles and associated entities. Occasionally, due to complex changes in investor access or organizational mappings, this cache might need to be manually refreshed to ensure the user has the correct level of visibility.

## Purpose
The **Reset Access Rights Cache** feature allows administrators to manually trigger a full rebuild of a user's permission cache. This ensures that the user's data visibility is accurately reflected based on their current authorized access rights.

## Who Can Use This?
This feature is restricted to:
- **Company Administrators**: Can reset the cache for users within their own entity.
- **Support Users**: Can reset the cache for any user across the system.

## How to Reset the Cache

1.  **Navigate to the User Profile**:
    *   Go to the **Users** management page.
    *   Click on the name of the user whose cache needs to be reset to view their details page.

2.  **Trigger the Reset**:
    *   Locate the **Reset Access Rights Cache** button at the bottom of the user's profile page.
    *   Click the button. A confirmation dialog will appear.
    *   Confirm the action.

3.  **Wait for Completion**:
    *   The reset process is performed in the background to ensure the platform remains responsive.
    *   You will see a notification: *"Access rights cache reset has been enqueued. You will receive a notification when it's done."*
    *   Once the background process is complete, you will receive a system notification indicating whether the reset was successful or if an error occurred.

## Technical Details
- The reset process clears the existing `access_rights_cache` and rebuilds it by iterating through all `AccessRight` and `InvestorAccess` records associated with the user.
- The process is handled by a background job (`ResetAccessRightsCacheJob`) to manage performance for users with extensive access mappings.
- System notifications are broadcasted to the initiating administrator via the `UserAlert` mechanism.
