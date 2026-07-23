import frappe

frappe.init('site1.local', sites_path='/home/frappe/frappe-bench/sites')
frappe.connect()
frappe.session.user = "Administrator"
frappe.clear_cache()

print("=== TEST 1: Save with Mobile, WITHOUT Email (should succeed) ===")
try:
    doc = frappe.get_doc({
        "doctype": "Student",
        "first_name": "TestMobileOnly",
        "student_mobile_number": "01712345678",
    })
    doc.insert(ignore_permissions=True)
    print(f"  PASS: Created Student {doc.name}")
    print(f"  student_email_id = '{doc.student_email_id}'")
    print(f"  student_mobile_number = '{doc.student_mobile_number}'")
    test1_name = doc.name
except Exception as e:
    print(f"  FAIL: {type(e).__name__}: {e}")
    test1_name = None

print()
print("=== TEST 2: Save WITHOUT Mobile (should fail with validation error) ===")
try:
    doc2 = frappe.get_doc({
        "doctype": "Student",
        "first_name": "TestNoMobile",
        "student_email_id": "nomobile@test.local",
    })
    doc2.insert(ignore_permissions=True)
    print(f"  FAIL: Should have thrown error but got {doc2.name}")
    test2_name = doc2.name
except Exception as e:
    err = str(e)
    if "mobile" in err.lower() or "required" in err.lower():
        print(f"  PASS: Got expected error: {err}")
    else:
        print(f"  UNEXPECTED: {type(e).__name__}: {err}")
    test2_name = None

print()
print("=== TEST 3: Save WITHOUT Email AND WITH Mobile (no crash) ===")
try:
    doc3 = frappe.get_doc({
        "doctype": "Student",
        "first_name": "TestSafeNoEmail",
        "student_mobile_number": "01812345678",
    })
    doc3.insert(ignore_permissions=True)
    print(f"  PASS: Created {doc3.name}, email='{doc3.student_email_id}', mobile='{doc3.student_mobile_number}'")
    test3_name = doc3.name
except Exception as e:
    print(f"  FAIL: {type(e).__name__}: {e}")
    test3_name = None

frappe.db.commit()

print()
print("=== CLEANUP ===")
for n in [test1_name, test2_name, test3_name]:
    if n:
        try:
            frappe.delete_doc("Student", n, force=True)
            print(f"  Deleted {n}")
        except:
            print(f"  Failed to delete {n}")

frappe.db.commit()
print("Done.")
frappe.destroy()
