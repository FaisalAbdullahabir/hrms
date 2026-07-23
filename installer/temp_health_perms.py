import frappe, json, os
os.chdir('/home/frappe/frappe-bench/sites')

# Enable dev mode
with open('site1.local/site_config.json', 'r+') as f:
    cfg = json.load(f)
    cfg['developer_mode'] = 1
    f.seek(0)
    json.dump(cfg, f, indent=2)
    f.truncate()

frappe.init('site1.local')
frappe.connect()

# Fix permissions - no submit since not submittable
dt = frappe.get_doc("DocType", "Student Health Record")
dt.permissions = []
dt.append("permissions", {"role": "System Manager", "read": 1, "write": 1, "create": 1, "delete": 1, "print": 1, "email": 1, "export": 1})
dt.append("permissions", {"role": "Academics User", "read": 1, "write": 1, "create": 1, "print": 1, "email": 1})
dt.append("permissions", {"role": "School Nurse", "read": 1, "write": 1, "create": 1, "delete": 1, "print": 1, "email": 1, "export": 1})
dt.save(ignore_permissions=True)
frappe.db.commit()
frappe.clear_cache()
print("Permissions updated")

# Verify
meta = frappe.get_meta("Student Health Record")
for p in meta.permissions:
    print(f"  {p.role}: read={p.read}, write={p.write}, create={p.create}")

# Fix BMI for existing records
records = frappe.get_all("Student Health Record", fields=["name", "height_cm", "weight_kg"])
for rec in records:
    if rec.height_cm and rec.weight_kg:
        height_m = rec.height_cm / 100.0
        bmi_val = round(rec.weight_kg / (height_m * height_m), 2)
        frappe.db.set_value("Student Health Record", rec.name, "bmi", bmi_val)
        print(f"  BMI for {rec.name}: {bmi_val}")
frappe.db.commit()

# Disable dev mode
with open('site1.local/site_config.json', 'r+') as f:
    cfg2 = json.load(f)
    cfg2['developer_mode'] = 0
    f.seek(0)
    json.dump(cfg2, f, indent=2)
    f.truncate()
print("Dev mode disabled")

frappe.destroy()
