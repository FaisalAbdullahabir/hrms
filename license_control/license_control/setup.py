import frappe


def after_install():
    """Create License Status Single DocType record if not exists."""
    if not frappe.db.exists("License Status", "License Status"):
        doc = frappe.get_doc(
            {
                "doctype": "License Status",
                "doctype_name": "License Status",
            }
        )
        doc.insert(ignore_permissions=True)
        frappe.db.commit()
