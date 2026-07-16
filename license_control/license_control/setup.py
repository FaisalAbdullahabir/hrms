import frappe


def after_install():
    """Create License Status Single DocType with pending_setup status."""
    if not frappe.db.exists("License Status", "License Status"):
        doc = frappe.get_doc({"doctype": "License Status"})
        doc.insert(ignore_permissions=True)
        frappe.db.commit()

    frappe.db.set_single_value("License Status", "status", "pending_setup")
    frappe.db.commit()
