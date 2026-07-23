import frappe
from frappe.model.document import Document


class StudentHealthRecord(Document):
    def validate(self):
        self.calculate_bmi()

    def calculate_bmi(self):
        if self.height_cm and self.weight_kg:
            height_m = self.height_cm / 100.0
            self.bmi = round(self.weight_kg / (height_m * height_m), 2)
        else:
            self.bmi = 0
