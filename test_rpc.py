import urllib.request, json, base64

host = 'http://localhost:7350'

# Auth
req = urllib.request.Request(
    host + '/v2/account/authenticate/device?create=true',
    data=json.dumps({'id': 'debug-test-abc'}).encode(),
    headers={'Content-Type': 'application/json'}
)
req.add_header('Authorization', 'Basic ' + base64.b64encode(b'defaultkey:').decode())
resp = json.loads(urllib.request.urlopen(req).read())
token = resp['token']
print(f'Auth OK')

# Call debug RPC
req2 = urllib.request.Request(
    host + '/v2/rpc/list_rooms',
    data='"{}"'.encode(),
    headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token}
)
result = json.loads(urllib.request.urlopen(req2).read())
print(f'Debug result: {result["payload"]}')
