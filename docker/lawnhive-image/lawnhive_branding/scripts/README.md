# License Control — Setup Guide

## Quick Start

### 1. Google Cloud Console (Browser — Manual)

1. Go to https://console.cloud.google.com
2. Click project dropdown → "New Project" → Name: `LawnHive License API` → Create
3. Search "Google Sheets API" → Click → "Enable"
4. Go to "IAM & Admin" → "Service Accounts" → "Create Service Account"
   - Name: `license-sheet-bot`
   - Click "Create and Continue" → Skip roles → "Done"
5. Click the service account → "Keys" tab → "Add Key" → "Create new key" → JSON → Download
6. Save as `credentials.json` in this directory

### 2. Share Google Sheet (Browser — Manual)

1. Open your Google Sheet
2. Click "Share" (top right)
3. Paste the service account email (from step 4 above, looks like `license-sheet-bot@project.iam.gserviceaccount.com`)
4. Set permission to "Editor"
5. Click "Send"

### 3. Run Setup Script (Terminal)

```bash
pip install gspread google-auth
python setup_license_sheet.py
```

### 4. Deploy Apps Script (Browser — Manual)

1. Open your Google Sheet
2. Go to Extensions → Apps Script
3. Delete any existing code, paste `license_api.gs` content
4. Click "Deploy" → "New deployment"
5. Select type: "Web app"
6. Description: "LawnHive License API"
7. Execute as: "Me"
8. Who has access: "Anyone"
9. Click "Deploy"
10. Copy the Web App URL

### 5. Configure LawnHive Workspace (Browser — Manual)

1. Open your LawnHive Workspace desk
2. Go to License Status (Single DocType)
3. Paste the Web App URL into "License API URL" field
4. Save

### 6. Install license_control App (Terminal)

```bash
cd /home/frappe/frappe-bench
bench get-app /path/to/license_control
bench --site site1.local install-app license_control
bench --site site1.local migrate
```

## Manual Checklist

- [ ] Google Cloud project created
- [ ] Sheets API enabled
- [ ] Service Account created + credentials.json downloaded
- [ ] Google Sheet shared with service account (Editor)
- [ ] `setup_license_sheet.py` run successfully
- [ ] Apps Script pasted + deployed as Web App
- [ ] Web App URL copied into License Status DocType
- [ ] `license_control` app installed + migrated

## Testing

1. Open LawnHive Workspace desk
2. Check sidebar — if client_type is "ngo", Manufacturing/CRM/Selling/Buying/Stock/Quality/Support should be hidden
3. Change client_type to "business" in Google Sheet
4. Wait 1 hour (or run `bench execute license_control.tasks.apply_module_visibility`)
5. Check sidebar — all modules should reappear
