import frappe, json, os
os.chdir('/home/frappe/frappe-bench/sites')
frappe.init('site1.local')
frappe.connect()

results = {}

# Fix Workspace - use Link type like existing shortcuts
try:
    ws = frappe.get_doc("Workspace", "Education")
    existing_labels = [l.label for l in ws.links] if ws.links else []
    
    if "Student Health Record" not in existing_labels:
        ws.append("links", {
            "type": "Link",
            "link_type": "Document Type",
            "label": "Student Health Record",
            "doctype": "Student Health Record",
            "onboard": 1,
        })
        ws.save(ignore_permissions=True)
        frappe.db.commit()
        results["workspace"] = "shortcut added"
    else:
        results["workspace"] = "already exists"
except Exception as e:
    results["workspace_error"] = str(e)[:500]
    frappe.db.rollback()

# Create custom BMI report for chart data
try:
    report_name = "BMI Growth Report"
    if not frappe.db.exists("Report", report_name):
        report = frappe.get_doc({
            "doctype": "Report",
            "report_name": report_name,
            "ref_doctype": "Student Health Record",
            "report_type": "Script Report",
            "is_standard": "No",
            "module": "Education",
        })
        report.insert(ignore_permissions=True)
        
        # Create the script file
        script_path = '/home/frappe/frappe-bench/apps/education/education/report/bmi_growth_report/'
        os.makedirs(script_path, exist_ok=True)
        
        with open(os.path.join(script_path, 'bmi_growth_report.py'), 'w') as f:
            f.write('''import frappe

def execute(filters=None):
    columns = [
        {"fieldname": "date_of_record", "fieldtype": "Date", "label": "Date", "width": 120},
        {"fieldname": "student", "fieldtype": "Link", "options": "Student", "label": "Student", "width": 150},
        {"fieldname": "height_cm", "fieldtype": "Float", "label": "Height (cm)", "width": 100},
        {"fieldname": "weight_kg", "fieldtype": "Float", "label": "Weight (kg)", "width": 100},
        {"fieldname": "bmi", "fieldtype": "Float", "label": "BMI", "width": 80},
    ]
    
    conditions = ""
    if filters.get("student"):
        conditions += " AND student = %(student)s"
    
    data = frappe.db.sql("""
        SELECT date_of_record, student, height_cm, weight_kg, bmi
        FROM `tabStudent Health Record`
        WHERE docstatus = 1 {conditions}
        ORDER BY date_of_record ASC
    """.format(conditions=conditions), filters, as_dict=True)
    
    return columns, data
''')
        
        with open(os.path.join(script_path, '__init__.py'), 'w') as f:
            f.write('')
        
        frappe.db.commit()
        results["report"] = "created"
    else:
        results["report"] = "already exists"
except Exception as e:
    results["report_error"] = str(e)[:300]
    frappe.db.rollback()

frappe.db.commit()
print(json.dumps(results, indent=2))
frappe.destroy()
