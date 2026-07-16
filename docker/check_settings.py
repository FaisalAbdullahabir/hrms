import frappe, os
os.chdir("/home/frappe/frappe-bench/sites")
frappe.connect("site1.local")

ws = frappe.get_doc("Workspace", "Settings")
print(f"Workspace: {ws.name}")
print(f"  public: {ws.public}")
print(f"  is_hidden: {ws.is_hidden}")
print(f"  links count: {len(ws.links) if ws.links else 0}")

# Check erpnext-settings redirect
print(f"\n  URL slug: /app/settings")
print(f"  Redirect from /app/erpnext-settings: JS-based")

frappe.destroy()
