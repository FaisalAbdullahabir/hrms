import frappe
frappe.connect("site1.local")
for ws in frappe.get_all("Workspace", fields=["name", "module", "is_hidden"]):
    print(ws.name + " | " + ws.module + " | hidden=" + str(ws.is_hidden))
frappe.destroy()
