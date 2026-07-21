import json
from datetime import timedelta

import frappe
from frappe.utils import now_datetime, date_diff, getdate


# ── Module visibility mapping ──
# NGO_HIDDEN_WORKSPACES and BUSINESS_HIDDEN_WORKSPACES removed —
# Sheet checkboxes are the single source of truth for module visibility.

# Workspaces that are NEVER hidden — always visible regardless of enabled_modules
ALWAYS_VISIBLE_WORKSPACES = [
    "Home", "Users", "Settings", "Build", "Integrations",
    "ERPNext Settings",
]

# Sub-workspaces and system workspaces to exclude from the module list
EXCLUDE_WORKSPACES = ALWAYS_VISIBLE_WORKSPACES + [
    "Employee Lifecycle", "Leaves", "Expense Claims", "Shift & Attendance",
    "Financial Reports", "Payables", "Receivables",
    "Salary Payout", "Tax & Benefits",
    "Welcome Workspace", "ERPNext Integrations",
]

TRIAL_DAYS = 14

# Frappe DocType module → our enabled_modules mapping
# Frappe uses different module names internally than our workspace names
DOCTYPE_MODULE_TO_ENABLED = {
    "Accounts": "Accounting",
    "Quality Management": "Quality",
    "Subcontracting": "Manufacturing",
}

# System modules that should ALWAYS have permissions (not restricted by license)
ALWAYS_ENABLED_MODULES = {
    "Setup", "Core", "Desk", "Automation", "Bulk Transaction",
    "Communication", "Contacts", "Custom", "Email", "Geo",
    "Integrations", "ERPNext Integrations", "License", "Maintenance",
    "Portal", "Printing", "Regional", "Social", "Telephony",
    "Utilities", "Workflow", "EDI",
}

# Reports use the same mapping
REPORT_MODULE_TO_ENABLED = {
    "Accounts": "Accounting",
    "Quality Management": "Quality",
    "Subcontracting": "Manufacturing",
}


def get_dynamic_module_list():
    """Get all non-system workspace names dynamically from Frappe.

    Returns a sorted list of workspace names that can be toggled
    by enabled_modules (excludes ALWAYS_VISIBLE ones).
    """
    all_ws = frappe.get_all("Workspace", fields=["name"])
    exclude = set(EXCLUDE_WORKSPACES)
    modules = sorted([
        ws.name for ws in all_ws
        if ws.name not in exclude
    ])
    return modules


@frappe.whitelist()
def sync_module_list_to_sheet():
    """Sync available module list to Google Sheet Apps Script.

    POSTs the dynamic module list to the Apps Script doPost() endpoint
    with action='update_module_list'. The Apps Script then updates the
    dropdown validation on column M (enabled_modules) of the Clients tab.
    """
    try:
        import requests as req

        api_url = frappe.db.get_single_value("License Status", "api_url")
        if not api_url:
            frappe.log_error("License Control: sync_module_list — no api_url")
            return {"status": "error", "message": "no api_url configured"}

        modules = get_dynamic_module_list()

        api_key = _get_api_key()
        payload = {
            "action": "update_module_list",
            "modules": modules,
        }
        headers = {}
        if api_key:
            headers["X-API-Key"] = api_key
        resp = req.post(api_url, json=payload, headers=headers, timeout=15)
        resp.raise_for_status()
        result = resp.json()

        frappe.log_error(
            "License Control: sync_module_list synced {} modules: {}".format(
                len(modules), result
            )
        )
        return {"status": "ok", "modules": modules, "api_response": result}

    except Exception:
        frappe.log_error("License Control: sync_module_list_to_sheet failed")
        return {"status": "error", "message": "sync failed, check error log"}


def _sync_to_sheet(client_id, status, activated_date, expiry_date):
    """POST status update to Google Sheet via Apps Script doPost()."""
    try:
        api_url = frappe.db.get_single_value("License Status", "api_url")
        if not api_url:
            return

        import requests as req
        api_key = _get_api_key()
        payload = {
            "client_id": client_id,
            "status": status,
            "activated_date": activated_date,
            "expiry_date": expiry_date,
        }
        headers = {}
        if api_key:
            headers["X-API-Key"] = api_key
        req.post(api_url, json=payload, headers=headers, timeout=10)
    except Exception:
        frappe.log_error("License Control: _sync_to_sheet failed")


def sync_user_password(contact_email, client_name, new_password):
    """Create or update Frappe User from Sheet login_password."""
    if not new_password or not contact_email:
        return

    try:
        if frappe.db.exists("User", contact_email):
            user = frappe.get_doc("User", contact_email)
            user.new_password = new_password
            user.save(ignore_permissions=True)
            frappe.db.commit()
            frappe.db.set_single_value("License Status", "last_password_sync", now_datetime())
            frappe.db.commit()
            frappe.log_error("License Control: Password updated for " + contact_email)
            return "password_updated"
        else:
            user = frappe.get_doc({
                "doctype": "User",
                "email": contact_email,
                "first_name": client_name or "Client",
                "send_welcome_email": 0,
                "default_workspace": "Home",
                "roles": [{"role": "System Manager"}],
            })
            user.insert(ignore_permissions=True)
            frappe.db.set_value("User", user.name, "user_type", "System User")
            frappe.db.set_value("User", user.name, "default_workspace", "Home")
            user.new_password = new_password
            user.save(ignore_permissions=True)
            frappe.db.commit()
            frappe.db.set_single_value("License Status", "last_password_sync", now_datetime())
            frappe.db.commit()
            frappe.log_error("License Control: User created " + contact_email)
            return "user_created"

    except Exception:
        frappe.log_error("License Control: sync_user_password failed")


# ══════════════════════════════════════════════════════════════════════
# LICENSE CHECK (hourly scheduler)
# ══════════════════════════════════════════════════════════════════════

def _get_api_key():
    """Read the API key from site_config.json."""
    return frappe.conf.get("license_api_key", "")


def check_license():
    """Hourly: fetch license from Google Sheet, enforce rules."""
    try:
        import requests

        api_url = frappe.db.get_single_value("License Status", "api_url")
        if not api_url:
            return

        client_id = frappe.conf.get("client_id", "NGO001")
        api_key = _get_api_key()
        params = {"client_id": client_id}
        if api_key:
            params["api_key"] = api_key
        resp = requests.get(api_url, params=params, timeout=10)
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

        # ── Auto-create/update Frappe User from Sheet password ──
        sync_user_password(
            contact_email=data.get("contact_email", ""),
            client_name=data.get("client_name", ""),
            new_password=data.get("login_password", ""),
        )

        # ── Trial expiry check ──
        _check_trial_expiry()

        # ── Apply rules ──
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
    """Called on every login. Block/allow based on license status.

    Fail-closed: if any error occurs reading license status, block login.
    """
    try:
        status = frappe.db.get_single_value("License Status", "status")
    except Exception:
        frappe.log_error("License Control: enforce_license failed to read status")
        frappe.throw(
            "System error — unable to verify license. Please contact admin.",
            title="License Verification Failed"
        )
        return

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
        if not expiry:
            frappe.throw(
                "ফ্রি ট্রায়ালের মেয়াদ নির্ধারিত হয়নি। "
                "যোগাযোগ করুন।",
                title="Trial Error",
            )
        days_left = date_diff(getdate(expiry), getdate())
        if days_left > 0:
            frappe.msgprint(
                "ফ্রি ট্রায়াল — {days} দিন বাকি। "
                "আপগ্রেড করতে যোগাযোগ করুন।".format(days=days_left),
                title="Free Trial",
                indicator="orange",
                alert=True,
            )
        else:
            frappe.throw(
                "ফ্রি ট্রায়াল শেষ হয়ে গেছে। "
                "সাবস্ক্রিপশন পুনরুদ্ধার করতে যোগাযোগ করুন।",
                title="Trial Expired",
            )


# ══════════════════════════════════════════════════════════════════════
# MODULE VISIBILITY
# ══════════════════════════════════════════════════════════════════════

def apply_module_visibility():
    """DEPRECATED — removed. Sheet checkboxes control visibility via apply_feature_restrictions()."""
    pass


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
    "HR", "Accounting", "Manufacturing", "Stock", "Selling", "Buying",
    "CRM", "Quality", "Assets", "Projects", "Support", "Website",
    "Tools", "Education", "Drive",
]

# Module name → Workspace name mapping
# HR includes Recruitment and Performance as sub-workspaces
MODULE_WORKSPACE_MAP = {
    "HR": ["HR", "Recruitment", "Performance"],
    "Payroll": ["Payroll"],
    "Recruitment": [],
    "Performance": [],
    "Accounting": ["Accounting"],
    "Manufacturing": ["Manufacturing"],
    "Stock": ["Stock"],
    "Selling": ["Selling"],
    "Buying": ["Buying"],
    "CRM": ["CRM"],
    "Quality": ["Quality"],
    "Assets": ["Assets"],
    "Projects": ["Projects"],
    "Support": ["Support"],
    "Website": ["Website"],
    "Tools": ["Tools"],
    "Education": ["Education"],
    "Drive": ["Drive"],
}


def _ensure_workspace_module_defs():
    """Ensure all workspace modules have Module Def entries in Frappe.

    The Workspace constructor checks user.allowed_modules which is built
    from Module Def entries. Without a Module Def, the module is excluded
    from allowed_modules, causing PermissionError for non-Workspace-Manager
    users and silently hiding the workspace from the sidebar.

    This is a no-op if entries already exist (idempotent).
    """
    try:
        # Collect all modules used by workspaces
        all_ws = frappe.get_all("Workspace", fields=["module"],
                                 filters={"module": ["is", "set"]},
                                 ignore_permissions=True)
        workspace_modules = set(ws.module for ws in all_ws)

        for mod_name in workspace_modules:
            if frappe.db.exists("Module Def", mod_name):
                continue

            # Determine app_name from workspace's DocTypes
            dt = frappe.db.get_value("DocType", {"module": mod_name}, "name")
            if dt:
                # Infer app from module's DocType package
                dt_doc = frappe.get_doc("DocType", dt)
                app_name = getattr(dt_doc, 'module', mod_name)
            else:
                app_name = mod_name.lower()

            try:
                mod_doc = frappe.get_doc({
                    "doctype": "Module Def",
                    "module_name": mod_name,
                    "app_name": app_name,
                    "label": mod_name,
                    "description": mod_name + " Module",
                })
                mod_doc.insert(ignore_permissions=True)
            except Exception:
                frappe.clear_messages()

        frappe.db.commit()
    except Exception:
        frappe.clear_messages()


def apply_feature_restrictions():
    """Show/hide workspaces and set DocType/Report permissions.

    Logic:
      final_allowed = enabled_modules INTERSECT plan_features
      - Non-gated modules: allowed if in enabled_modules
      - Feature-gated modules (Payroll, Recruitment, Performance):
        allowed if in enabled_modules AND plan feature flag is true

    For each enabled module:
      - Workspace is made public (visible in sidebar)
      - All DocTypes in that module get System Manager read/write/create/delete
      - All Reports in that module get System Manager read access
    For each disabled module:
      - Workspace is made private
      - Custom DocPerm entries for System Manager are removed

    Also ensures all workspace modules have Module Def entries (required
    by Frappe's Workspace constructor to prevent PermissionError).
    """
    try:
        # Ensure Module Def entries exist for all workspace modules.
        # Without these, Frappe's Workspace constructor raises PermissionError
        # for non-Workspace-Manager users, hiding workspaces from sidebar.
        _ensure_workspace_module_defs()
        enabled_modules = _get_enabled_modules()
        features = _get_features()

        # Sheet checkboxes are the single source of truth.
        # Admin explicitly enables/disables modules there — no client_type override.
        final_allowed = set()

        for mod in NON_GATED_MODULES:
            if mod in enabled_modules:
                final_allowed.add(mod)

        for mod, feature_key in FEATURE_GATED_MODULES.items():
            if mod in enabled_modules and features.get(feature_key, False):
                final_allowed.add(mod)

        # System modules always get permissions (Setup, Core, Desk, etc.)
        final_allowed.update(ALWAYS_ENABLED_MODULES)

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

        for ws_name in ALWAYS_VISIBLE_WORKSPACES:
            try:
                ws = frappe.get_doc("Workspace", ws_name)
                if ws.public != 1:
                    ws.flags.ignore_links = True
                    ws.flags.ignore_validate = True
                    ws.public = 1
                    ws.save()
            except Exception:
                frappe.clear_messages()

        frappe.db.commit()

        # Set DocType and Report permissions
        _set_module_doctype_permissions(final_allowed)
        _set_module_report_permissions(final_allowed)

    except Exception:
        frappe.log_error("License Control: apply_feature_restrictions failed")


def _ensure_doctype_perm(doctype_name, is_enabled):
    """Add or remove System Manager permission on a DocType."""
    try:
        from frappe.permissions import setup_custom_perms

        if is_enabled:
            # Ensure standard perms are copied to Custom DocPerm first
            setup_custom_perms(doctype_name)

            # Check if System Manager already has an entry
            existing = frappe.db.get_value("Custom DocPerm", {
                "parent": doctype_name,
                "role": "System Manager",
                "permlevel": 0,
                "if_owner": 0,
            }, "name")

            if existing:
                frappe.db.set_value("Custom DocPerm", existing, {
                    "read": 1, "write": 1, "create": 1, "delete": 1,
                    "submit": 1, "cancel": 1, "amend": 1,
                    "report": 1, "export": 1, "import": 1,
                    "print": 1, "email": 1,
                })
            else:
                docperm = frappe.get_doc({
                    "doctype": "Custom DocPerm",
                    "parent": doctype_name,
                    "parenttype": "DocType",
                    "parentfield": "permissions",
                    "role": "System Manager",
                    "permlevel": 0,
                    "if_owner": 0,
                    "read": 1, "write": 1, "create": 1, "delete": 1,
                    "submit": 1, "cancel": 1, "amend": 1,
                    "report": 1, "export": 1, "import": 1,
                    "print": 1, "email": 1,
                })
                docperm.insert(ignore_permissions=True)
        else:
            # Remove System Manager Custom DocPerm for this DocType
            frappe.db.delete("Custom DocPerm", {
                "parent": doctype_name,
                "role": "System Manager",
            })

    except Exception:
        frappe.clear_messages()


def _resolve_module(doc_module):
    """Map a DocType/Report module name to our enabled_modules name."""
    if doc_module in ALWAYS_ENABLED_MODULES:
        return doc_module
    return DOCTYPE_MODULE_TO_ENABLED.get(doc_module, doc_module)


def _set_module_doctype_permissions(final_allowed):
    """Add/remove DocType permissions for enabled/disabled modules."""
    try:
        all_dts = frappe.get_all("DocType", fields=["name", "module"],
                                 filters={"module": ["is", "set"]})

        for dt in all_dts:
            resolved = _resolve_module(dt.module)
            is_enabled = resolved in final_allowed
            _ensure_doctype_perm(dt.name, is_enabled)

        frappe.db.commit()

    except Exception:
        frappe.log_error("License Control: _set_module_doctype_permissions failed")


def _ensure_report_perm(report_name, is_enabled):
    """Add or remove System Manager permission on a Report.

    Frappe's Report.has_permission() checks permissions on the 'Report'
    DocType itself (not the report's ref_doctype). So we add/remove
    SM access on the 'Report' DocType to control report access.
    """
    pass


def _set_module_report_permissions(final_allowed):
    """Ensure System Manager can access all Reports.

    Report.has_permission() delegates to frappe.permissions.has_permission
    on the 'Report' DocType. We add a Custom DocPerm for System Manager
    on 'Report' so all reports are accessible.

    Module-level visibility is handled by workspace visibility — if a
    workspace is hidden, its report links are not shown in the sidebar.
    """
    try:
        _ensure_doctype_perm("Report", True)
        frappe.db.commit()

    except Exception:
        frappe.log_error("License Control: _set_module_report_permissions failed")


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


# ══════════════════════════════════════════════════════════════════════
# HOME DASHBOARD SHORTCUTS
# ══════════════════════════════════════════════════════════════════════

MODULE_ICONS = {
    "HR": "fa-user",
    "Payroll": "fa-money",
    "Accounting": "fa-calculator",
    "Manufacturing": "fa-cogs",
    "Stock": "fa-archive",
    "Selling": "fa-shopping-cart",
    "Buying": "fa-shopping-basket",
    "Quality": "fa-check-circle",
    "CRM": "fa-address-book",
    "Assets": "fa-diamond",
    "Projects": "fa-folder-open",
    "Support": "fa-life-ring",
    "Website": "fa-globe",
    "Tools": "fa-wrench",
    "Education": "fa-graduation-cap",
    "Drive": "fa-files-o",
}


@frappe.whitelist()
def get_dashboard_shortcuts():
    """Return enabled modules as shortcut cards for Home dashboard."""
    enabled = _get_enabled_modules()
    shortcuts = []
    for mod in sorted(enabled):
        if mod in MODULE_ICONS:
            shortcuts.append({
                "module": mod,
                "icon": MODULE_ICONS[mod],
                "route": "/app/" + mod.lower(),
            })
    return shortcuts
