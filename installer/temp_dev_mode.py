import frappe, json, os
os.chdir('/home/frappe/frappe-bench/sites')
frappe.init('site1.local')
frappe.connect()

results = {}

# 1. Enable developer mode in site_config
try:
    with open('site1.local/site_config.json', 'r+') as f:
        cfg = json.load(f)
        cfg['developer_mode'] = 1
        f.seek(0)
        json.dump(cfg, f, indent=2)
        f.truncate()
    results['dev_mode'] = 'enabled'
except Exception as e:
    results['dev_mode_error'] = str(e)

# 2. Create School Nurse role first
try:
    if not frappe.db.exists("Role", "School Nurse"):
        role = frappe.get_doc({
            "doctype": "Role",
            "role_name": "School Nurse",
            "desk_access": 1,
        })
        role.insert(ignore_permissions=True)
        frappe.db.commit()
        results['role'] = 'created'
    else:
        results['role'] = 'already exists'
except Exception as e:
    results['role_error'] = str(e)[:300]
    frappe.db.rollback()

print(json.dumps(results, indent=2))
frappe.db.commit()
frappe.destroy()
