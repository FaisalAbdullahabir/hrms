import frappe, json, os
os.chdir('/home/frappe/frappe-bench/sites')
frappe.init('site1.local')
frappe.connect()

results = {}

# Fix Chart - needs based_on for time series
try:
    if not frappe.db.exists("Dashboard Chart", "BMI Growth - Student"):
        chart = frappe.get_doc({
            "doctype": "Dashboard Chart",
            "chart_name": "BMI Growth - Student",
            "chart_type": "Line",
            "document_type": "Student Health Record",
            "based_on": "date_of_record",
            "x_field": "date_of_record",
            "y_axis": [{"field": "bmi", "label": "BMI"}],
            "filters_json": json.dumps([]),
            "number_format": "#.##",
            "timespan": "All",
            "time_interval": "Monthly",
            "color": "#f59f36",
            "owner": "Administrator",
        })
        chart.insert(ignore_permissions=True)
        frappe.db.commit()
        results["chart"] = "created"
    else:
        results["chart"] = "already exists"
except Exception as e:
    results["chart_error"] = str(e)[:500]
    frappe.db.rollback()

# Fix Workspace - check correct format
try:
    ws = frappe.get_doc("Workspace", "Education")
    # Check what types are valid
    existing_types = set()
    for link in ws.links:
        existing_types.add(link.type)
    results["existing_link_types"] = list(existing_types)
    
    # Check if shortcut already exists
    existing_labels = [l.label for l in ws.links] if ws.links else []
    results["existing_labels"] = existing_labels
    
    if "Student Health Record" not in existing_labels:
        # Use the same type as existing DocType links
        ws.append("links", {
            "type": "DocType",
            "link_type": "Document",
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

# Disable developer mode
try:
    with open('site1.local/site_config.json', 'r+') as f:
        cfg = json.load(f)
        cfg['developer_mode'] = 0
        f.seek(0)
        json.dump(cfg, f, indent=2)
        f.truncate()
    results['dev_mode'] = 'disabled'
except Exception as e:
    results['dev_mode_error'] = str(e)

frappe.db.commit()
print(json.dumps(results, indent=2))
frappe.destroy()
