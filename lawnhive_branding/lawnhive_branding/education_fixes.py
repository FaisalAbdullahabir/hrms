"""
Education module UX fixes for LawnHive Workspace.

Fixes:
1. Student: ensure student_email_id is set before validate_user runs
2. Student Group: set default group_based_on = "Course"
"""
import frappe


def student_before_insert(doc, method):
    """Ensure student has a valid email before validate_user() runs."""
    if not doc.student_email_id:
        # Generate a placeholder email from the student name
        name_part = (doc.first_name or "student").lower().replace(" ", ".")
        doc.student_email_id = f"{name_part}@placeholder.local"


def student_group_before_insert(doc, method):
    """Set default group_based_on if not set."""
    if not doc.group_based_on:
        doc.group_based_on = "Course"
