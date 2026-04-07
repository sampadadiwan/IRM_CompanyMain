# User Guide: Entity Database Dumps

The Investor Relationship Management (IRM) system provides an automated feature to generate portable SQLite database dumps for each entity. These dumps contain a fund-specific slice of data, allowing for offline analysis, backups, and data portability.

---

## 1. Overview

Database dumps are generated as SQLite `.sqlite3` files and stored as **Documents** within the entity's "Temp" folder. The generation process can be automated based on a schedule or triggered manually by an administrator.

---

## 2. Configuring Dump Settings

To configure database dumps for your entity, navigate to the **Entity Settings** page (usually via the Admin dashboard or Entity edit page).

### Key Settings:

| Setting | Description |
| :--- | :--- |
| **Enable Database Dumps** | Master toggle to turn the feature on or off. |
| **Dump Frequency** | Determines how often the automated system should generate a new dump. |
| **Retention Period (Days)** | How many days to keep old dumps before they are automatically deleted (default: 7). |
| **Enable Email Notifications** | If enabled, specified users will receive an email with a download link when a new dump is ready. |

---

## 3. Frequency Options

The system supports several scheduling options to match your data backup needs:

*   **Daily (Default):** Generates one dump every 24 hours.
*   **Weekly:** Generates one dump per calendar week.
*   **Monthly:** Generates one dump per calendar month.
*   **Interval:** Generates a dump every `N` days (e.g., every 10 days). 
    *   *Requires setting the **Interval (Days)** field.*
*   **Custom Days:** Generates a dump only on specific days of the week (e.g., "Monday, Thursday").
    *   *Requires setting the **Custom Days** field with comma-separated day names.*
*   **Adhoc:** Disables all automated/periodic dumps. Dumps will only be generated when manually triggered by a user.

---

## 4. Manual (Adhoc) Generation

Administrators can trigger a database dump at any time by clicking the **Generate DB Dump** button on the Entity show page.

### Important Notes on Manual Triggers:
*   **Frequency Protection:** Even when triggered manually, the system respects the configured frequency (except for the "Adhoc" setting). For example, if the frequency is "Daily" and a dump was already taken this morning, clicking the button again will skip the generation to prevent redundant files.
*   **Adhoc Setting:** If the frequency is set to "Adhoc", the manual trigger will always proceed immediately.
*   **Notifications:** If a manual request is skipped due to frequency limits, the user will receive an on-screen notification explaining why.

---

## 5. Accessing the Dumps

Once generated, the SQLite files are stored in the document management system:

1.  Navigate to the **Documents** section of your Entity.
2.  Open the **Temp** folder.
3.  Look for files named `DB Dump YYYY-MM-DD HH:MM`.
4.  You can download these files and open them using any SQLite browser (e.g., DB Browser for SQLite).

---

## 6. Notifications

To receive email notifications when a dump is ready:
1.  Ensure **Enable Email Notifications** is checked in Entity Settings.
2.  Add the tag `db_dump_notification` to the user profiles of the employees who should receive the emails.

---

## 7. Technical Details

*   **Trigger Mechanism:** Automated dumps are evaluated and triggered daily at **01:30 AM** (as part of the `DailyMorningJob`).
*   **Cleanup:** The system automatically deletes old dumps that exceed the **Retention Period** every time a new dump is successfully generated.
*   **Multi-Tenancy:** Dumps are strictly scoped to the entity's data, ensuring complete isolation between different clients in the system.
