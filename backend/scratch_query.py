import base64
import urllib.request
import json

token = base64.b64encode(b"admin:admin123").decode("utf-8")
req = urllib.request.Request(
    "http://localhost:8001/admin/ccl/balances",
    headers={"Authorization": f"Bearer {token}"}
)
try:
    with urllib.request.urlopen(req) as response:
        print("Status:", response.status)
        data = json.loads(response.read().decode('utf-8'))
        print("Body:", json.dumps(data, indent=2))
except Exception as e:
    print("Error:", e)
