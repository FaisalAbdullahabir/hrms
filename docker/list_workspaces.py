import frappe
frappe.connect("site1.local")
for ws in frappe.get_all("Workspace", fields=["name", "module", "is_hidden"]):
    print(f"  {ws.name} | module={ws.module} | hidden={ws.is_hidden}")
frappe.destroy()
