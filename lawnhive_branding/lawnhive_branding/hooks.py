app_name = "lawnhive_hr"
app_title = "LawnHive HR"
app_description = "LawnHive HR & Payroll Management System"
app_publisher = "LawnHive"
app_email = "info@lawnhive.com"
app_license = "MIT"

# ── Branding Identity ──
app_logo_url = "/assets/lawnhive_branding/images/logo.png"
splash_image = "/assets/lawnhive_branding/images/logo.png"
app_icon = "icon-umbrella"
app_color = "#f59f36"

# ── JS/CSS Includes (Desk) ──
app_include_css = "/assets/lawnhive_branding/css/lawnhive_theme.css?v=14"
app_include_js = [
    "/assets/lawnhive_branding/js/lawnhive_branding.js?v=11",
    "/assets/lawnhive_branding/js/floating_badge.js?v=1",
]

# ── Website Context (login + public pages) ──
website_context = {
    "favicon": "/assets/lawnhive_branding/images/favicon.png",
}
web_include_css = ["/assets/lawnhive_branding/css/lawnhive_theme.css?v=14"]
web_include_js = [
    "/assets/lawnhive_branding/js/lawnhive_branding.js?v=11",
    "/assets/lawnhive_branding/js/floating_badge.js?v=1",
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

# ── Jinja Helpers ──
jinja = {
    "methods": [
        "lawnhive_branding.utils.get_lawnhive_year",
    ],
}
