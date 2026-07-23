import frappe

frappe.session.user = "Administrator"
result = frappe.call("frappe.desk.desktop.get_workspace_sidebar_items")
pages = result.get("pages", [])
edu_children = [p for p in pages if p.get("parent_page") == "Education"]
print(f"Found {len(edu_children)} Education sub-workspaces:")
for p in edu_children:
    print(f"  - {p.get('label')} (name={p.get('name')})")
