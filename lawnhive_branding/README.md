# LawnHive Branding

Custom branding app for LawnHive Workspace — replaces all Frappe/ERPNext references with LawnHive identity.

## Installation

```bash
bench get-app /path/to/lawnhive_branding
bench --site site1.local install-app lawnhive_branding
bench build --app lawnhive_branding
bench restart
```

## Customization

Replace the placeholder images with your real logo:

- `lawnhive_branding/public/images/logo.png` — App logo (shown in sidebar, navbar, about dialog)
- `lawnhive_branding/public/images/favicon.png` — Browser tab icon (16x16 or 32x32 recommended)

## What It Does

- Replaces Frappe/ERPNext branding with "LawnHive Workspace"
- Applies brand color #f59f36 across all UI elements
- Overrides About dialog and Help menu
- Sets up default letterhead and footer with auto-updating year
- Hides all Frappe/ERPNext references from client-facing pages
