import frappe, json, os
os.chdir('/home/frappe/frappe-bench/sites')
frappe.init('site1.local')
frappe.connect()

results = {}

# Permission test
frappe.set_user("teacher@test.com")
results["teacher_roles"] = frappe.get_roles("teacher@test.com")
results["can_read_doc"] = frappe.has_permission("Student Health Record", "read")
results["can_write_doc"] = frappe.has_permission("Student Health Record", "write")
results["can_create_doc"] = frappe.has_permission("Student Health Record", "create")
frappe.set_user("Administrator")

results["admin_roles"] = frappe.get_roles("Administrator")
results["admin_can_read"] = frappe.has_permission("Student Health Record", "read")
results["admin_can_write"] = frappe.has_permission("Student Health Record", "write")

frappe.db.commit()
print(json.dumps(results, indent=2))
frappe.destroy()
