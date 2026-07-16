import json
from datetime import timedelta

import frappe
from frappe.utils import now_datetime, date_diff, getdate


# ── Module visibility mapping ──
NGO_HIDDEN_WORKSPACES = [
    "Manufacturing", "CRM", "Selling", "Buying",
    "Stock", "Quality", "Support",
]
BUSINESS_HIDDEN_WORKSPACES = []

TRIAL_DAYS = 14


def _sync_to_sheet(client_id, status, activated_date, expiry_date):
    """POST status update to Google Sheet via Apps Script doPost()."""
    try:
        api_url = frappe.db.get_single_value("License Status", "api_url")
        if not api_url:
            return

        import requests as req
        payload = {
            "client_id": client_id,
            "status": status,
            "activated_date": activated_date,
            "expiry_date": expiry_date,
        }
        req.post(api_url, json=payload, timeout=10)
    except Exception:
        frappe.log_error("License Control: _sync_to_sheet failed")


# ══════════════════════════════════════════════════════════════════════
# LICENSE CHECK (hourly scheduler)
# ══════════════════════════════════════════════════════════════════════

def check_license():
    """Hourly: fetch license from Google Sheet, enforce rules."""
    try:
        import requests

        api_url = frappe.db.get_single_value("License Status", "api_url")
        if not api_url:
            return

        client_id = frappe.conf.get("client_id", "NGO001")
        resp = requests.get(api_url, params={"client_id": client_id}, timeout=10)
        resp.raise_for_status()
        data = resp.json()

        if data.get("status") == "not_found":
            frappe.log_error("License Control: client_id not found in Sheet")
            return

        # ── First run: pending_setup → free_trial ──
        current_status = frappe.db.get_single_value("License Status", "status")
        if current_status == "pending_setup" or not current_status:
            today = getdate()
            expiry = today + timedelta(days=TRIAL_DAYS)
            frappe.db.set_single_value("License Status", "status", "free_trial")
            frappe.db.set_single_value("License Status", "activated_date", str(today))
            frappe.db.set_single_value("License Status", "expiry_date", str(expiry))
            frappe.db.commit()
            current_status = "free_trial"

            # Sync back to Google Sheet via doPost()
            _sync_to_sheet(client_id, "free_trial", str(today), str(expiry))

        # ── Sync fields from Sheet ──
        updates = {}
        for key in ["client_id", "client_name", "client_type", "status", "plan",
                     "activated_date", "expiry_date"]:
            if data.get(key):
                updates[key] = data[key]
        updates["last_check_in"] = now_datetime()

        if data.get("features"):
            updates["features"] = json.dumps(data["features"])

        if data.get("enabled_modules"):
            em = data["enabled_modules"]
            if isinstance(em, list):
                updates["enabled_modules"] = json.dumps(em)
            elif isinstance(em, str):
                updates["enabled_modules"] = json.dumps(
                    [m.strip() for m in em.split(",") if m.strip()]
                )

        for field, value in updates.items():
            frappe.db.set_single_value("License Status", field, value)
        frappe.db.commit()

        # ── Trial expiry check ──
        _check_trial_expiry()

        # ── Apply rules ──
        apply_module_visibility()
        apply_feature_restrictions()
        _check_trial_reminder()

    except Exception:
        frappe.log_error("License Control: check_license failed")


# ══════════════════════════════════════════════════════════════════════
# TRIAL EXPIRY AUTO-CHECK
# ══════════════════════════════════════════════════════════════════════

def _check_trial_expiry():
    """If trial expired, set status to inactive in Sheet via API."""
    try:
        status = frappe.db.get_single_value("License Status", "status")
        if status != "free_trial":
            return

        expiry = frappe.db.get_single_value("License Status", "expiry_date")
        if not expiry:
            return

        if getdate(expiry) < getdate():
            # Trial expired → notify via flag
            frappe.db.set_single_value("License Status", "status", "inactive")
            frappe.db.commit()
            frappe.log_error("License Control: Trial expired, status set to inactive")
    except Exception:
        frappe.log_error("License Control: _check_trial_expiry failed")


# ══════════════════════════════════════════════════════════════════════
# TRIAL REMINDER (3 days before expiry)
# ══════════════════════════════════════════════════════════════════════

def _check_trial_reminder():
    """Create notification if trial expires within 3 days."""
    try:
        status = frappe.db.get_single_value("License Status", "status")
        if status != "free_trial":
            return

        expiry = frappe.db.get_single_value("License Status", "expiry_date")
        if not expiry:
            return

        days_left = date_diff(getdate(expiry), getdate())
        if 0 < days_left <= 3:
            _create_trial_notification(days_left)
    except Exception:
        frappe.log_error("License Control: _check_trial_reminder failed")


def _create_trial_notification(days_left):
    """Create a Frappe Notification visible on admin dashboard."""
    try:
        title = "ট্রায়াল শেষ হতে চলেছে"
        message = (
            "আপনার ফ্রি ট্রায়াল {days} দিনের মধ্যে শেষ হবে। "
            "সাবস্ক্রিপশন আপগ্রেড করতে যোগাযোগ করুন।"
        ).format(days=days_left)

        # Avoid duplicate notifications
        existing = frappe.db.exists("Notification", {
            "subject": title,
            "creation": [">", frappe.utils.add_days(getdate(), -1)]
        })
        if existing:
            return

        notification = frappe.get_doc({
            "doctype": "Notification",
            "subject": title,
            "message": message,
            "document_type": "License Status",
            "event": "Custom",
            "channel": "Notification",
            "roles": [{"role": "System Manager"}],
        })
        notification.insert(ignore_permissions=True)
        frappe.db.commit()
    except Exception:
        frappe.log_error("License Control: _create_trial_notification failed")


# ══════════════════════════════════════════════════════════════════════
# ENFORCE LICENSE (login hook)
# ══════════════════════════════════════════════════════════════════════

def enforce_license(login_manager=None):
    """Called on every login. Block/allow based on license status."""
    try:
        status = frappe.db.get_single_value("License Status", "status")

        if status == "pending_setup":
            frappe.throw(
                "অ্যাকাউন্ট এখনো সক্রিয় করা হয়নি। "
                "দয়া করে সিস্টেম অ্যাডমিনের সাথে যোগাযোগ করুন।",
                title="Account Not Activated"
            )

        if status == "inactive":
            frappe.throw(
                "সাবস্ক্রিপশন নিষ্ক্রিয়। "
                "সাবস্ক্রিপশন পুনরুদ্ধার করতে যোগাযোগ করুন।",
                title="Subscription Inactive"
            )

        if status == "free_trial":
            expiry = frappe.db.get_single_value("License Status", "expiry_date")
            if expiry:
                days_left = date_diff(getdate(expiry), getdate())
                if days_left > 0:
                    frappe.msgprint(
                        "ফ্রি ট্রায়াল — {days} দিন বাকি। "
                        "আপগ্রেড করতে যোগাযোগ করুন।".format(days=days_left),
                        title="Free Trial",
                        indicator="orange",
                        alert=True,
                    )

    except Exception:
        pass


# ══════════════════════════════════════════════════════════════════════
# MODULE VISIBILITY
# ══════════════════════════════════════════════════════════════════════

def apply_module_visibility():
    """Show/hide workspaces based on client_type."""
    try:
        client_type = frappe.db.get_single_value("License Status", "client_type")
        if not client_type:
            return

        hidden = NGO_HIDDEN_WORKSPACES if client_type == "ngo" else BUSINESS_HIDDEN_WORKSPACES

        all_ws = [
            "Home", "Assets", "Accounting", "Buying", "CRM",
            "Manufacturing", "Quality", "Selling", "Stock", "Support",
        ]

        for ws_name in all_ws:
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


# ══════════════════════════════════════════════════════════════════════
# FEATURE RESTRICTIONS
# ══════════════════════════════════════════════════════════════════════

def _get_features():
    raw = frappe.db.get_single_value("License Status", "features")
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return {}


def _get_enabled_modules():
    raw = frappe.db.get_single_value("License Status", "enabled_modules")
    if not raw:
        return set()
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, list):
            return set(parsed)
    except (json.JSONDecodeError, TypeError):
        pass
    return set(m.strip() for m in raw.split(",") if m.strip())


# Modules that require plan feature flags
FEATURE_GATED_MODULES = {
    "Payroll": "payroll",
    "Recruitment": "recruitment",
    "Performance": "performance",
}

# Modules that only need enabled_modules (no plan flag needed)
NON_GATED_MODULES = [
    "HR", "Manufacturing", "Stock", "Selling", "Buying",
    "CRM", "Quality", "Assets", "Projects",
]

# Module name → Workspace name mapping
MODULE_WORKSPACE_MAP = {
    "HR": ["HR"],
    "Payroll": ["Payroll"],
    "Recruitment": [],
    "Performance": [],
    "Manufacturing": ["Manufacturing"],
    "Stock": ["Stock"],
    "Selling": ["Selling"],
    "Buying": ["Buying"],
    "CRM": ["CRM"],
    "Quality": ["Quality"],
    "Assets": ["Assets"],
    "Projects": ["Projects"],
}


def apply_feature_restrictions():
    """Show/hide workspaces based on intersection of enabled_modules and plan features.

    Logic:
      final_allowed = enabled_modules INTERSECT plan_features
      - HR, Manufacturing, Stock, Selling, Buying, CRM, Quality, Assets, Projects:
        allowed if in enabled_modules (admin's choice is final)
      - Payroll, Recruitment, Performance:
        allowed if in enabled_modules AND plan feature flag is true
      - NGO hidden modules are always hidden regardless of enabled_modules
    """
    try:
        enabled_modules = _get_enabled_modules()
        features = _get_features()
        client_type = frappe.db.get_single_value("License Status", "client_type") or ""

        ngo_hidden = set(NGO_HIDDEN_WORKSPACES) if client_type == "ngo" else set()

        # Build final_allowed_modules
        final_allowed = set()

        # Non-gated modules: only need enabled_modules
        for mod in NON_GATED_MODULES:
            if mod in enabled_modules and mod not in ngo_hidden:
                final_allowed.add(mod)

        # Feature-gated modules: need enabled_modules + plan feature flag
        for mod, feature_key in FEATURE_GATED_MODULES.items():
            if (mod in enabled_modules
                    and features.get(feature_key, False)
                    and mod not in ngo_hidden):
                final_allowed.add(mod)

        # Show/hide workspaces
        for mod, ws_list in MODULE_WORKSPACE_MAP.items():
            should_be_visible = mod in final_allowed
            for ws_name in ws_list:
                try:
                    ws = frappe.get_doc("Workspace", ws_name)
                    new_public = 1 if should_be_visible else 0
                    if ws.public != new_public:
                        ws.flags.ignore_links = True
                        ws.flags.ignore_validate = True
                        ws.public = new_public
                        ws.save()
                except Exception:
                    frappe.clear_messages()

        frappe.db.commit()

    except Exception:
        frappe.log_error("License Control: apply_feature_restrictions failed")


# ══════════════════════════════════════════════════════════════════════
# EMPLOYEE LIMIT
# ══════════════════════════════════════════════════════════════════════

def check_employee_limit():
    """Before inserting an Employee, check max_employees from plan."""
    features = _get_features()
    max_emp = features.get("max_employees", 0)
    if not max_emp:
        return

    current_count = frappe.db.count("Employee", {"status": "Active"})
    if current_count >= max_emp:
        frappe.throw(
            "আপনার প্ল্যানের employee লিমিট শেষ ({limit} জন)। "
            "আপগ্রেড করুন।".format(limit=max_emp),
            title="Employee Limit Reached"
        )
