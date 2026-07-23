import frappe, json, os
os.chdir('/home/frappe/frappe-bench/sites')
frappe.init('site1.local')
frappe.connect()

results = {}

# Test 1: BMI is correct
records = frappe.get_all("Student Health Record", fields=["name", "student", "height_cm", "weight_kg", "bmi", "date_of_record"], order_by="date_of_record desc")
results["records"] = []
for r in records:
    expected = round(r.weight_kg / ((r.height_cm / 100.0) ** 2), 2)
    results["records"].append({
        "name": r.name, "height": r.height_cm, "weight": r.weight_kg,
        "bmi": r.bmi, "expected": expected, "correct": r.bmi == expected
    })

# Test 2: PDF Health Card
try:
    from frappe.utils.pdf import get_pdf
    html = frappe.get_print("Student Health Record", records[0].name, print_format="Student Health Card")
    pdf = get_pdf(html)
    results["pdf_ok"] = True
    results["pdf_size"] = len(pdf)
except Exception as e:
    results["pdf_error"] = str(e)[:300]

# Test 3: Permission - teacher WITHOUT School Nurse should be BLOCKED
try:
    frappe.set_user("teacher@test.com")
    try:
        doc = frappe.get_doc("Student Health Record", records[0].name)
        results["permission"] = "FAIL - teacher CAN read (should not)"
    except Exception as e:
        if "permission" in str(e).lower():
            results["permission"] = "PASS - teacher blocked"
        else:
            results["permission"] = f"Other error: {str(e)[:200]}"
    frappe.set_user("Administrator")
except Exception as e:
    results["permission_error"] = str(e)[:200]
    frappe.set_user("Administrator")

frappe.db.commit()
print(json.dumps(results, indent=2, default=str))
frappe.destroy()
