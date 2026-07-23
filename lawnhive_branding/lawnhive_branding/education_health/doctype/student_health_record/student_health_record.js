frappe.ui.form.on("Student Health Record", {
    height_cm: function(frm) {
        calculate_bmi(frm);
    },
    weight_kg: function(frm) {
        calculate_bmi(frm);
    },
    refresh: function(frm) {
        calculate_bmi(frm);
    }
});

function calculate_bmi(frm) {
    var height = frm.doc.height_cm;
    var weight = frm.doc.weight_kg;
    if (height && weight && height > 0) {
        var height_m = height / 100.0;
        var bmi = weight / (height_m * height_m);
        frm.set_value("bmi", Math.round(bmi * 100) / 100);
    }
}
