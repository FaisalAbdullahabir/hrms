import frappe


def after_install():
    _setup_website_settings()
    _setup_navbar_settings()
    _setup_system_settings()
    _setup_letterhead()
    _setup_workspace_rename()
    frappe.db.commit()


def _setup_website_settings():
    ws = frappe.get_single("Website Settings")

    has_lawnhive = any(
        f.get("title") == "LawnHive" for f in ws.footer_items
    )
    if not has_lawnhive:
        ws.append("footer_items", {
            "parent": "Footer",
            "title": "LawnHive",
            "label": "LawnHive",
            "url": "https://lawnhive.com/",
            "target": "_blank",
        })

    ws.app_name = "LawnHive Workspace"
    ws.app_logo = "/assets/lawnhive_branding/images/logo.png"
    ws.favicon = "/assets/lawnhive_branding/images/favicon.png"
    ws.splash_image = "/assets/lawnhive_branding/images/logo.png"
    ws.footer_logo = "/assets/lawnhive_branding/images/logo.png"
    ws.footer_powered = ""
    ws.copyright = ""

    ws.save(ignore_permissions=True)


def _setup_navbar_settings():
    try:
        ns = frappe.get_single("Navbar Settings")
        ns.app_logo = "/assets/lawnhive_branding/images/logo.png"
        ns.app_name = "LawnHive Workspace"
        ns.save(ignore_permissions=True)
    except Exception:
        pass


def _setup_system_settings():
    try:
        ss = frappe.get_single("System Settings")
        ss.app_name = "LawnHive Workspace"
        ss.save(ignore_permissions=True)
    except Exception:
        pass


def _setup_letterhead():
    if frappe.db.exists("Letter Head", "LawnHive Default"):
        return

    lh = frappe.get_doc({
        "doctype": "Letter Head",
        "letter_head_name": "LawnHive Default",
        "source": "HTML",
        "content": (
            '<div style="text-align:center; padding:20px 0; border-bottom:3px solid #f59f36;">'
            '<h1 style="color:#f59f36; margin:0; font-size:24px;">LawnHive</h1>'
            '<p style="color:#666; margin:5px 0 0 0; font-size:12px;">'
            "Workspace for Business Operations | "
            '<a href="https://lawnhive.com/" style="color:#f59f36;">www.lawnhive.com</a>'
            "</p></div>"
        ),
        "is_default": 1,
    })
    lh.insert(ignore_permissions=True)


def _setup_workspace_rename():
    """Rename 'ERPNext Settings' workspace label to 'Settings'."""
    try:
        ws = frappe.get_doc("Workspace", "ERPNext Settings")
        ws.label = "Settings"
        ws.title = "Settings"
        ws.save(ignore_permissions=True)
    except Exception:
        pass
