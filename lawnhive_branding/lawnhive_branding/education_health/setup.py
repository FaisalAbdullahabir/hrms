"""
Setup Student Health Record feature:
1. Create School Nurse role
2. Create BMI Growth dashboard chart
3. Create Student Health Card print format
4. Add Education workspace shortcut
"""
import frappe, json


def setup_all():
    results = {}

    # ── 1. Create School Nurse Role ──
    try:
        if not frappe.db.exists("Role", "School Nurse"):
            role = frappe.get_doc({
                "doctype": "Role",
                "role_name": "School Nurse",
                "desk_access": 1,
                "is_custom": 0,
                "is_system": 0,
                "restrict_to_domain": "Education",
                "role_type": "Reporting",
            })
            role.insert(ignore_permissions=True)
            frappe.db.commit()
            results["role"] = "created"
        else:
            results["role"] = "already exists"
    except Exception as e:
        results["role_error"] = str(e)[:300]
        frappe.db.rollback()

    # ── 2. Grant School Nurse role to Administrator ──
    try:
        admin_user = frappe.get_doc("User", "Administrator")
        role_names = [r.role for r in admin_user.roles]
        if "School Nurse" not in role_names:
            admin_user.append("roles", {"role": "School Nurse"})
            admin_user.save(ignore_permissions=True)
            frappe.db.commit()
            results["admin_role"] = "granted"
        else:
            results["admin_role"] = "already has role"
    except Exception as e:
        results["admin_role_error"] = str(e)[:300]
        frappe.db.rollback()

    # ── 3. Create BMI Growth Chart ──
    try:
        chart_name = "BMI Growth - Student"
        if not frappe.db.exists("Dashboard Chart", chart_name):
            chart = frappe.get_doc({
                "doctype": "Dashboard Chart",
                "chart_name": chart_name,
                "chart_type": "Line",
                "document_type": "Student Health Record",
                "x_field": "date_of_record",
                "y_axis": [{"field": "bmi", "label": "BMI"}],
                "filters_json": json.dumps([["Student Health Record", "student", "=", ""]]),
                "number_format": "#.##",
                "timespan": "All",
                "time_interval": "Monthly",
                "color": "#f59f36",
                "custom_options": json.dumps({
                    "axisOptions": {"xAxis": {"showLabel": True}},
                }),
            })
            chart.insert(ignore_permissions=True)
            frappe.db.commit()
            results["chart"] = "created"
        else:
            results["chart"] = "already exists"
    except Exception as e:
        results["chart_error"] = str(e)[:300]
        frappe.db.rollback()

    # ── 4. Create Student Health Card Print Format ──
    try:
        pf_name = "Student Health Card"
        if not frappe.db.exists("Print Format", pf_name):
            pf = frappe.get_doc({
                "doctype": "Print Format",
                "name": pf_name,
                "module": "Education",
                "doc_type": "Student Health Record",
                "print_format_type": "Jinja",
                "custom_format": 1,
                "standard": "No",
                "html": """
<div style="font-family: Arial, sans-serif; padding: 20px; max-width: 800px; margin: 0 auto;">
  <div style="text-align: center; border-bottom: 3px solid #f59f36; padding-bottom: 15px; margin-bottom: 20px;">
    <h1 style="color: #21537a; margin: 0;">Student Health Card</h1>
    <p style="color: #666; margin: 5px 0 0 0;">LawnHive Workspace — Education</p>
  </div>

  <div style="display: flex; gap: 20px; margin-bottom: 20px;">
    <div style="flex: 1; background: #f8f9fa; padding: 15px; border-radius: 8px;">
      <h3 style="color: #21537a; margin-top: 0;">Student Information</h3>
      <p><strong>Name:</strong> {{ doc.student_name or doc.student }}</p>
      <p><strong>Student ID:</strong> {{ doc.student }}</p>
      <p><strong>Date of Record:</strong> {{ frappe.utils.format_date(doc.date_of_record) }}</p>
    </div>
    <div style="flex: 1; background: #f8f9fa; padding: 15px; border-radius: 8px;">
      <h3 style="color: #21537a; margin-top: 0;">Physical Measurements</h3>
      <p><strong>Height:</strong> {{ doc.height_cm }} cm</p>
      <p><strong>Weight:</strong> {{ doc.weight_kg }} kg</p>
      <p><strong>BMI:</strong> {{ doc.bmi }}</p>
    </div>
  </div>

  {% if doc.emergency_medical_instructions %}
  <div style="background: #fff3cd; padding: 15px; border-radius: 8px; border-left: 4px solid #ffc107; margin-bottom: 20px;">
    <h3 style="color: #856404; margin-top: 0;">⚠ Emergency Medical Information</h3>
    <p style="white-space: pre-wrap;">{{ doc.emergency_medical_instructions }}</p>
  </div>
  {% endif %}

  {% if doc.special_needs %}
  <div style="background: #d1ecf1; padding: 15px; border-radius: 8px; border-left: 4px solid #17a2b8; margin-bottom: 20px;">
    <h3 style="color: #0c5460; margin-top: 0;">Special Needs</h3>
    <p>{{ doc.special_needs_description or "No details provided" }}</p>
  </div>
  {% endif %}

  {% if doc.health_checkup_history %}
  <div style="margin-bottom: 20px;">
    <h3 style="color: #21537a;">Recent Health Checkups</h3>
    <table style="width: 100%; border-collapse: collapse;">
      <thead>
        <tr style="background: #21537a; color: white;">
          <th style="padding: 8px; text-align: left;">Date</th>
          <th style="padding: 8px; text-align: left;">Findings</th>
          <th style="padding: 8px; text-align: left;">Examiner</th>
        </tr>
      </thead>
      <tbody>
        {% for item in doc.health_checkup_history[-5:] %}
        <tr style="border-bottom: 1px solid #ddd;">
          <td style="padding: 8px;">{{ frappe.utils.format_date(item.checkup_date) }}</td>
          <td style="padding: 8px;">{{ item.findings }}</td>
          <td style="padding: 8px;">{{ item.examiner_name }}</td>
        </tr>
        {% endfor %}
      </tbody>
    </table>
  </div>
  {% endif %}

  {% if doc.medication_record %}
  <div style="margin-bottom: 20px;">
    <h3 style="color: #21537a;">Current Medications</h3>
    <table style="width: 100%; border-collapse: collapse;">
      <thead>
        <tr style="background: #21537a; color: white;">
          <th style="padding: 8px; text-align: left;">Medicine</th>
          <th style="padding: 8px; text-align: left;">Dosage</th>
          <th style="padding: 8px; text-align: left;">Period</th>
          <th style="padding: 8px; text-align: left;">Prescribed By</th>
        </tr>
      </thead>
      <tbody>
        {% for item in doc.medication_record %}
        <tr style="border-bottom: 1px solid #ddd;">
          <td style="padding: 8px;">{{ item.medicine_name }}</td>
          <td style="padding: 8px;">{{ item.dosage }}</td>
          <td style="padding: 8px;">{{ frappe.utils.format_date(item.start_date) }} - {{ frappe.utils.format_date(item.end_date) if item.end_date else "Ongoing" }}</td>
          <td style="padding: 8px;">{{ item.prescribed_by }}</td>
        </tr>
        {% endfor %}
      </tbody>
    </table>
  </div>
  {% endif %}

  <div style="text-align: center; color: #999; font-size: 11px; border-top: 1px solid #ddd; padding-top: 10px; margin-top: 20px;">
    Generated by LawnHive Workspace | {{ frappe.utils.nowdate() }}
  </div>
</div>
""",
            })
            pf.insert(ignore_permissions=True)
            frappe.db.commit()
            results["print_format"] = "created"
        else:
            results["print_format"] = "already exists"
    except Exception as e:
        results["print_format_error"] = str(e)[:300]
        frappe.db.rollback()

    # ── 5. Create Education sub-workspaces ──
    try:
        from lawnhive_branding.education_health.workspace_setup import setup_education_workspaces
        ws_results = setup_education_workspaces()
        results["education_workspaces"] = ws_results
    except Exception as e:
        results["education_workspaces_error"] = str(e)[:300]
        frappe.db.rollback()

    print(json.dumps(results, indent=2))
    return results
