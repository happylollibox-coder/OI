import urllib.request
import json

req = urllib.request.Request('http://localhost:8080/api/scheduled-shipments')
try:
    with urllib.request.urlopen(req) as response:
        data = json.loads(response.read().decode())
        sugg = [x for x in data if x.get('product') == 'Blue Lollibox' and x.get('shipment_type_name') == 'Q4_BULK']
        print(f"Found {len(sugg)} Q4_BULK shipments for Blue Lollibox")
        if sugg:
            print("Sample:", sugg[0])
except Exception as e:
    print("Error:", e)
