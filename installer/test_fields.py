import json
d = json.load(open("/home/frappe/frappe-bench/apps/frappe/frappe/desk/doctype/workspace_link/workspace_link.json"))
for f in d.get("fields", []):
    print(f['fieldname'], f['fieldtype'])
