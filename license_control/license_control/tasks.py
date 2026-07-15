import frappe
import requests
from frappe.utils import now_datetime


# ── Module visibility mapping ──
# Workspaces to HIDE for each client type
NGO_HIDDEN_WORKSPACES = [
    "Manufacturing",
    "CRM",
    "Selling",
    "Buying",
    "Stock",
    "Quality",
    "Support",
]

BUSINESS_HIDDEN_WORKSPACES = []  # business clients see everything


def check_license():
    """Hourly task: fetch license data from Google Sheet via Apps Script API."""
    try:
        api_url = frappe.db.get_single_value("License Status", "api_url")
        if not api_url:
            return

        client_id = frappe.conf.get("client_id", "NGO001")
        resp = requests.get(
            api_url,
            params={"client_id": client_id},
            timeout=10,
        )
        resp.raise_for_status()
        data = resp.json()

        if data.get("status") == "not_found":
            frappe.log_error("License Control: client_id not found in Sheet")
            return

        doc = frappe.get_doc("License Status")
        doc.client_id = data.get("client_id", doc.client_id)
        doc.client_name = data.get("client_name", doc.client_name)
        doc.client_type = data.get("client_type", doc.client_type)
        doc.status = data.get("status", doc.status)
        doc.plan = data.get("plan", doc.plan)
        doc.activated_date = data.get("activated_date", doc.activated_date)
        doc.expiry_date = data.get("expiry_date", doc.expiry_date)
        doc.last_check_in = now_datetime()
        doc.save(ignore_permissions=True)
        frappe.db.commit()

        apply_module_visibility()

    except Exception:
        frappe.log_error("License Control: check_license failed")


def apply_module_visibility():
    """Show/hide workspaces based on client_type from License Status."""
    try:
        client_type = frappe.db.get_single_value("License Status", "client_type")
        if not client_type:
            return

        if client_type == "ngo":
            hidden = NGO_HIDDEN_WORKSPACES
        elif client_type == "business":
            hidden = BUSINESS_HIDDEN_WORKSPACES
        else:
            return

        all_erpnext_workspaces = [
            "Home", "Assets", "Accounting", "Buying", "CRM",
            "Manufacturing", "Quality", "Selling", "Stock", "Support",
        ]

        for ws_name in all_erpnext_workspaces:
            try:
                ws = frappe.get_doc("Workspace", ws_name)
                should_hide = ws_name in hidden
                new_public = 0 if should_hide else 1
                if ws.public != new_public:
                    ws.flags.ignore_links = True
                    ws.flags.ignore_validate = True
                    ws.public = new_public
                    ws.save()
            except Exception:
                frappe.clear_messages()

        frappe.db.commit()

    except Exception:
        frappe.log_error("License Control: apply_module_visibility failed")
