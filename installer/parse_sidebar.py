import json, sys
d = json.load(sys.stdin)
pages = [p for p in d.get('message', {}).get('pages', []) if p.get('parent_page') == 'Education']
print(f'{len(pages)} Education children:')
for p in pages:
    print(f'  {p["title"]}')
