$script = @"
import frappe
frappe.init('site1.local')
frappe.connect()
for dt in ['Employee Grade', 'Employment Type', 'Leave Type', 'Shift Type', 'Employee']:
    names = frappe.get_all(dt, pluck='name')
    print(f'--- {dt} ({len(names)}) ---')
    for n in names:
        print(f'  {n}')
frappe.destroy()
"@

$script | docker exec -i docker-frappe-1 bash -c 'cd /home/frappe/frappe-bench && ./env/bin/python3 -c "$(cat)"'
