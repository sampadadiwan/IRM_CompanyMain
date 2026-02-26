---
name: user-guide-expert
description: Generates and updates user-centric documentation in the `docs/` folder. Analyzes codebase (controllers, models, services, policies, notifications) to explain workflows, role-specific permissions, system side effects, and automated alerts.
---

# User Guide Expert Skill

This skill enables the agent to produce high-quality, accurate user documentation by bridging the gap between technical implementation and user-facing workflows.

## Documentation Workflow

### 1. Discovery & Analysis
Analyze the feature by examining the following in the relevant `app/packs/`:
- **Workflows**: Check `controllers` for actions and `views` for UI elements.
- **Roles**: Check `policies/` (Pundit) to see which roles (`admin`, `investor`, `advisor`, etc.) have access.
- **Business Logic**: Read `services/` and `models/` to find state transitions and data updates.
- **Side Effects**: Look for `after_save` callbacks, background jobs, or service-triggered updates.
- **Notifications**: Search for `Noticed` notifications, `Mailers`, or `Notifiers`.

### 2. Guide Structure
Every user guide should follow this general structure:

- **# [Feature Name] User Guide**
- **## 📖 Overview**: Brief explanation of the purpose of the feature.
- **## 👥 Roles & Permissions**: A table or list showing what each user role can do.
- **## 🚀 Workflows**:
    - Detailed steps for primary tasks.
    - Use "As an [Role], I can..." format where helpful.
- **## ⚙️ System Behavior & Side Effects**:
    - Explain what happens "under the hood" (e.g., "Deleting a document will also remove all its shared links").
    - Explain calculations or data aggregations.
- **## 🔔 Notifications**:
    - List what triggers an email, in-app notification, or WhatsApp message.
- **## 💡 Best Practices & Tips**: Pro-tips for using the feature effectively.

### 3. Writing Guidelines
- **Perspective**: Write for the user, not the developer.
- **Tone**: Professional, helpful, and clear.
- **Visuals**: Use Markdown tables, lists, and bold text for UI elements (e.g., "Click the **Approve** button").
- **Consistency**: Match the style of existing guides in `docs/`.

## Example Usage

### Commands
- `/skill:user-guide-expert generate a guide for the Capital Call workflow`
- `/skill:user-guide-expert update docs/kpi_upload_user_guide.md to include the new validation logic`

### Prompting the Agent
"Using the user-guide-expert skill, analyze `app/packs/funds/capital_calls` and write a guide for Fund Admins and Investors. Be sure to explain how the 'Call Amount' is calculated and what notifications are sent when a call is issued."
