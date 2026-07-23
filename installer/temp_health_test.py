import frappe, json, os
os.chdir('/home/frappe/frappe-bench/sites')
frappe.init('site1.local')
frappe.connect()

results = {}

# ── Test 1: Create test Student ──
try:
    student = frappe.get_doc({
        "doctype": "Student",
        "first_name": "Test",
        "last_name": "Health Student",
        "student_email_id": "test.health@example.com",
    })
    student.insert()
    frappe.db.commit()
    results["student"] = student.name
except Exception as e:
    results["student_error"] = str(e)[:300]
    frappe.db.rollback()

student_name = results.get("student", "")

# ── Test 2: Create Health Record with BMI ──
if student_name:
    try:
        hr = frappe.get_doc({
            "doctype": "Student Health Record",
            "student": student_name,
            "date_of_record": "2026-07-21",
            "height_cm": 150,
            "weight_kg": 45,
            "emergency_medical_instructions": "Blood Group: O+\nAllergy: Penicillin\nEmergency Contact: +8801712345678",
            "health_checkup_history": [
                {"checkup_date": "2026-07-21", "findings": "Healthy, no issues found", "examiner_name": "Dr. Rahman"},
            ],
            "medication_record": [
                {"medicine_name": "Vitamin D", "dosage": "1000 IU daily", "start_date": "2026-07-21", "prescribed_by": "Dr. Rahman"},
            ],
            "nurse_doctor_notes": [
                {"note_date": "2026-07-21", "note": "Student is in good health. BMI within normal range.", "author_name": "Nurse Fatima"},
            ],
        })
        hr.insert()
        frappe.db.commit()
        results["health_record"] = hr.name
        results["bmi_calculated"] = hr.bmi
        expected_bmi = round(45 / (1.5 * 1.5), 2)
        results["bmi_expected"] = expected_bmi
        results["bmi_correct"] = (hr.bmi == expected_bmi)
    except Exception as e:
        results["health_record_error"] = str(e)[:500]
        frappe.db.rollback()

# ── Test 3: Create second Health Record for chart data ──
if student_name:
    try:
        hr2 = frappe.get_doc({
            "doctype": "Student Health Record",
            "student": student_name,
            "date_of_record": "2026-01-15",
            "height_cm": 145,
            "weight_kg": 40,
        })
        hr2.insert()
        frappe.db.commit()
        results["health_record_2"] = hr2.name
        results["bmi_2"] = hr2.bmi
    except Exception as e:
        results["hr2_error"] = str(e)[:300]
        frappe.db.rollback()

# ── Test 4: PDF Health Card generation ──
if results.get("health_record"):
    try:
        from frappe.utils.pdf import get_pdf
        html = frappe.get_print("Student Health Record", results["health_record"], print_format="Student Health Card")
        pdf = get_pdf(html)
        results["pdf_generated"] = True
        results["pdf_size"] = len(pdf) if pdf else 0
    except Exception as e:
        results["pdf_error"] = str(e)[:500]

# ── Test 5: Permission - School Nurse can access ──
try:
    # Grant test user School Nurse role
    test_user = frappe.get_doc("User", "Administrator")
    roles = [r.role for r in test_user.roles]
    results["admin_roles_include_nurse"] = "School Nurse" in roles
except Exception as e:
    results["perm_check_error"] = str(e)[:300]

# ── Test 6: Permission - regular user WITHOUT School Nurse should be blocked ──
try:
    # Create a limited user without School Nurse or Academics User role
    if not frappe.db.exists("User", "teacher@test.com"):
        limited_user = frappe.get_doc({
            "doctype": "User",
            "email": "teacher@test.com",
            "first_name": "Test",
            "last_name": "Teacher",
            "user_type": "System User",
        })
        limited_user.add_roles("Employee")
        limited_user.save(ignore_permissions=True)
        frappe.db.commit()
    
    # Try to read health record as limited user (no School Nurse role)
    frappe.set_user("teacher@test.com")
    try:
        doc = frappe.get_doc("Student Health Record", results.get("health_record", ""))
        results["teacher_can_read"] = True
        results["permission_issue"] = "Teacher should NOT be able to read!"
    except Exception as e:
        if "does not have permission" in str(e).lower() or "permission" in str(e).lower():
            results["teacher_blocked"] = True
        else:
            results["teacher_other_error"] = str(e)[:300]
    frappe.set_user("Administrator")
except Exception as e:
    results["perm_test_error"] = str(e)[:300]
    frappe.set_user("Administrator")

frappe.db.commit()
print(json.dumps(results, indent=2, default=str))
frappe.destroy()
