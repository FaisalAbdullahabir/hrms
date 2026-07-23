import frappe, json, os
os.chdir('/home/frappe/frappe-bench/sites')
frappe.init('site1.local')
frappe.connect()

ws = frappe.get_doc("Workspace", "Education")
# Check existing link structure
for l in ws.links[:3]:
    print(f"  type={l.type}, link_type={l.get('link_type')}, label={l.label}, doctype={l.get('doctype', '')}")

# Add with correct format
existing_labels = [l.label for l in ws.links] if ws.links else []
if "Student Health Record" not in existing_labels:
    ws.append("links", {
        "type": "Link",
        "link_type": "DocType",
        "label": "Student Health Record",
    })
    ws.save(ignore_permissions=True)
    frappe.db.commit()
    print("Shortcut added!")
else:
    print("Already exists")

frappe.destroy()
