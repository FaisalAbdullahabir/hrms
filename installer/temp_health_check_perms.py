import frappe, json, os
os.chdir('/home/frappe/frappe-bench/sites')
frappe.init('site1.local')
frappe.connect()

# Check what permissions are actually set in the JSON
meta = frappe.get_meta("Student Health Record")
print("Meta permissions:")
for p in meta.permissions:
    print(f"  Role: {p.role}, read={p.read}, write={p.write}, create={p.create}")

# Check the actual JSON file
with open('/home/frappe/frappe-bench/apps/education/education/education/doctype/student_health_record/student_health_record.json') as f:
    dt_json = json.load(f)
print("\nJSON permissions:")
for p in dt_json.get('permissions', []):
    print(f"  Role: {p.get('role')}, read={p.get('read')}, write={p.get('write')}, create={p.get('create')}")

# Check if teacher user has any special permissions
print("\nTeacher roles:")
user_roles = frappe.get_roles("teacher@test.com")
print(f"  {user_roles}")

# Check if is_permitted works
frappe.set_user("teacher@test.com")
can_read = frappe.has_permission("Student Health Record", "read")
print(f"\nTeacher can read: {can_read}")
frappe.set_user("Administrator")

frappe.destroy()
