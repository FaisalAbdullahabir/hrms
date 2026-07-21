import frappe
from frappe.desk.desktop import get_workspace_sidebar_items

def execute():
    # Check roles
    roles = frappe.get_roles("Administrator")
    print("Administrator has Workspace Manager:", "Workspace Manager" in roles)
    
    roles2 = frappe.get_roles("admin@surovi.com") 
    print("admin@surovi.com has Workspace Manager:", "Workspace Manager" in roles2)
    
    # Simulate the sidebar query
    items = get_workspace_sidebar_items()
    pages = items.get("pages", [])
    print("\n=== Sidebar pages ({} total) ===".format(len(pages)))
    for p in pages:
        print("  {} (public={}, is_hidden={}, module={})".format(
            p.get("name", "?"), p.get("public", "?"), p.get("is_hidden", "?"), p.get("module", "?")))
    
    # Check which are missing
    all_ws = frappe.get_all("Workspace", fields=["name", "public", "is_hidden", "module"])
    all_names = set(ws.name for ws in all_ws)
    shown_names = set(p.get("name") for p in pages)
    missing = all_names - shown_names
    if missing:
        print("\n=== MISSING from sidebar ===")
        for ws in all_ws:
            if ws.name in missing:
                print("  {} (public={}, is_hidden={}, module={})".format(
                    ws.name, ws.public, ws.is_hidden, ws.module))
