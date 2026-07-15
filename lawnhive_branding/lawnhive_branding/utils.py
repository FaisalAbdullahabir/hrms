import frappe


@frappe.whitelist()
def get_about_info():
    """Return LawnHive info for the About dialog."""
    return {
        "app_name": "LawnHive HR",
        "version": frappe.get_version(),
        "publisher": "LawnHive",
        "website": "https://lawnhive.com/",
        "description": "HR & Payroll Management System",
    }


def get_lawnhive_year():
    """Return current year for footer copyright."""
    return frappe.utils.now_datetime().year


def add_website_css(context):
    """Inject LawnHive CSS on all website pages including login."""
    css_link = '<link rel="stylesheet" href="/assets/lawnhive_branding/css/lawnhive_theme.css">'
    js_link = '<script src="/assets/lawnhive_branding/js/lawnhive_branding.js"></script>'
    existing = context.get("head_include", "") or ""
    context["head_include"] = existing + css_link + js_link
