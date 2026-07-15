import frappe


def execute():
    """Rename/hide ERPNext workspaces to clean names."""
    # Rename ERPNext Settings -> Settings
    if frappe.db.exists("Workspace", "ERPNext Settings"):
        frappe.db.set_value("Workspace", "ERPNext Settings", "title", "Settings")
        frappe.db.set_value("Workspace", "ERPNext Settings", "label", "Settings")

    # Hide ERPNext Integrations (an "Integrations" workspace already exists)
    if frappe.db.exists("Workspace", "ERPNext Integrations"):
        frappe.db.set_value("Workspace", "ERPNext Integrations", "is_hidden", 1)

    frappe.db.commit()
