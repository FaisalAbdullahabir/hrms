import frappe

frappe.init('site1.local', sites_path='/home/frappe/frappe-bench/sites')
frappe.connect()
frappe.session.user = 'Administrator'

from frappe.desk.desktop import Workspace

sub_ws = ['Student Management', 'Academics', 'Admissions', 'Assessment', 'Fee Management', 'Attendance', 'Health Records']
all_ok = True
for ws_name in sub_ws:
    try:
        page = frappe.db.get_value('Workspace', ws_name, ['name', 'title', 'parent_page', 'content', 'public', 'module', 'icon', 'indicator_color', 'is_hidden'], as_dict=True)
        ws = Workspace(page)
        ws.build_workspace()
        cards = len(ws.cards.get('items', []))
        shortcuts = len(ws.shortcuts.get('items', []))
        card_labels = [c.get('label') for c in ws.cards.get('items', [])]
        sc_labels = [s.get('label') for s in ws.shortcuts.get('items', [])]
        print(f'OK: {ws_name} - cards={card_labels}, shortcuts={sc_labels}')
    except Exception as e:
        all_ok = False
        print(f'FAIL: {ws_name} - {type(e).__name__}: {e}')

if all_ok:
    print('\nAll 7 sub-workspaces PASSED!')
else:
    print('\nSome sub-workspaces FAILED!')

frappe.destroy()
