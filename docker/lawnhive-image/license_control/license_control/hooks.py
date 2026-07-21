app_name = "license_control"
app_title = "License Control"
app_description = "License tracking and module visibility control for LawnHive Workspace"
app_publisher = "LawnHive"
app_email = "info@lawnhive.com"
app_license = "MIT"

# ──────────────────────────────────────────────────────────────────────
# IMPORTANT: User authentication is handled entirely by Frappe's
# built-in User DocType and Role Permission Manager.
#
# The Google Sheet "Clients" tab stores contact_email, login_password,
# and contact_phone columns for admin/operational reference ONLY.
# These values are NEVER used for login or authentication.
#
# All login, session management, password hashing, 2FA, and role-based
# access control are managed by Frappe natively.
# ──────────────────────────────────────────────────────────────────────

scheduler_events = {
    "cron": {
        "*/5 * * * *": [
            "license_control.tasks.check_license",
        ],
    },
    "daily": [
        "license_control.tasks.sync_module_list_to_sheet",
    ],
}

# Login hook: enforce license status on every login
# "on_login" is the correct Frappe hook key (not "login")
# Called via LoginManager.post_login() → run_trigger("on_login")
on_login = "license_control.tasks.enforce_license"

doc_events = {
    "Employee": {
        "before_insert": "license_control.tasks.check_employee_limit"
    }
}

after_install = "license_control.setup.after_install"
