import frappe, json, os, sys
os.chdir('/home/frappe/frappe-bench/sites')
frappe.init('site1.local')
frappe.connect()

results = {}

# ── Import DocType JSON files directly ──
base_path = '/home/frappe/frappe-bench/apps/lawnhive_branding/lawnhive_branding/education_health/doctype'

# Order matters: child tables first, then parent
doctype_files = [
    ('Health Checkup Item', 'health_checkup_item/health_checkup_item.json'),
    ('Medication Item', 'medication_item/medication_item.json'),
    ('Nurse Doctor Note', 'nurse_doctor_note/nurse_doctor_note.json'),
    ('Student Health Record', 'student_health_record/student_health_record.json'),
]

for doctype_name, json_path in doctype_files:
    try:
        full_path = os.path.join(base_path, json_path)
        with open(full_path, 'r') as f:
            docjson = json.load(f)

        if frappe.db.exists('DocType', doctype_name):
            results[doctype_name] = 'already exists'
            continue

        # Create DocType using frappe's create_doc
        doc = frappe.get_doc(docjson)
        doc.flags.ignore_permissions = True
        doc.insert()
        frappe.db.commit()
        results[doctype_name] = 'created'
    except Exception as e:
        results[doctype_name] = f'error: {str(e)[:200]}'
        frappe.db.rollback()

frappe.db.commit()
print(json.dumps(results, indent=2))
frappe.destroy()
