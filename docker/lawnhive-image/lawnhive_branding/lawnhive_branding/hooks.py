app_name = "lawnhive_hr"
app_title = "LawnHive Workspace"
app_description = "LawnHive Workspace for Business Operations"
app_publisher = "LawnHive"
app_email = "info@lawnhive.com"
app_license = "MIT"

# ── Branding Identity ──
app_logo_url = "/assets/lawnhive_branding/images/logo.png"
splash_image = "/assets/lawnhive_branding/images/logo.png"
app_icon = "icon-umbrella"
app_color = "#f59f36"

# ── JS/CSS Includes (Desk) ──
app_include_css = "/assets/lawnhive_branding/css/lawnhive_theme.css?v=15"
app_include_js = [
    "/assets/lawnhive_branding/js/lawnhive_branding.js?v=12",
    "/assets/lawnhive_branding/js/floating_badge.js?v=1",
    "/assets/lawnhive_branding/js/rebrand_apps_page.js?v=2",
]

# ── Website Context (login + public pages) ──
website_context = {
    "favicon": "/assets/lawnhive_branding/images/favicon.png",
}
web_include_css = ["/assets/lawnhive_branding/css/lawnhive_theme.css?v=15"]
web_include_js = [
    "/assets/lawnhive_branding/js/lawnhive_branding.js?v=12",
    "/assets/lawnhive_branding/js/floating_badge.js?v=1",
    "/assets/lawnhive_branding/js/rebrand_apps_page.js?v=2",
]

# ── Fixtures ──
fixtures = [
    {
        "dt": "Website Settings",
        "filters": [["name", "=", "Website Settings"]],
    },
    {
        "dt": "Workspace",
        "filters": [["name", "in", ["ERPNext Settings"]]],
    },
]

# ── Setup Hooks ──
after_install = "lawnhive_branding.setup.after_install"

# ── Role → Home Page (skip /apps, go straight to /app/home) ──
role_home_page = {
    "System Manager": "/app/home",
    "HR Manager": "/app/home",
    "HR User": "/app/home",
    "Accounts Manager": "/app/home",
    "Accounts User": "/app/home",
    "Auditor": "/app/home",
    "Sales Manager": "/app/home",
    "Sales User": "/app/home",
    "Sales Master Manager": "/app/home",
    "Purchase Manager": "/app/home",
    "Purchase User": "/app/home",
    "Purchase Master Manager": "/app/home",
    "Stock Manager": "/app/home",
    "Stock User": "/app/home",
    "Manufacturing Manager": "/app/home",
    "Manufacturing User": "/app/home",
    "Quality Manager": "/app/home",
    "Projects Manager": "/app/home",
    "Projects User": "/app/home",
    "Leave Approver": "/app/home",
    "Expense Approver": "/app/home",
    "Item Manager": "/app/home",
    "Delivery Manager": "/app/home",
    "Delivery User": "/app/home",
    "Fleet Manager": "/app/home",
    "Maintenance Manager": "/app/home",
    "Maintenance User": "/app/home",
    "Support Team": "/app/home",
    "CRM Manager": "/app/home",
    "Newsletter Manager": "/app/home",
    "Inbox User": "/app/home",
    "Knowledge Base Contributor": "/app/home",
    "Knowledge Base Editor": "/app/home",
    "Blogger": "/app/home",
    "Website Manager": "/app/home",
    "Workspace Manager": "/app/home",
    "Dashboard Manager": "/app/home",
    "Report Manager": "/app/home",
    "Script Manager": "/app/home",
    "Prepared Report User": "/app/home",
    "Interviewer": "/app/home",
    "Academics User": "/app/home",
    "Agriculture Manager": "/app/home",
    "Agriculture User": "/app/home",
    "Fulfillment User": "/app/home",
    "Translator": "/app/home",
    "Desk User": "/app/home",
    "Guest": "/app/home",
    "All": "/app/home",
    "Administrator": "/app/home",
}

# ── Jinja Helpers ──
jinja = {
    "methods": [
        "lawnhive_branding.utils.get_lawnhive_year",
    ],
}

# ── Patches ──
patches = [
    "lawnhive_branding.patches.v1_0.add_contact_billing_column",
]

# ── Doc Events (Education UX fixes) ──
doc_events = {
    "Student": {
        "before_insert": "lawnhive_branding.education_fixes.student_before_insert",
    },
    "Student Group": {
        "before_insert": "lawnhive_branding.education_fixes.student_group_before_insert",
    },
}
