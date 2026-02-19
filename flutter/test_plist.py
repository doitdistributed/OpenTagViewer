import plistlib
import base64

data = base64.b64decode("rB31zgBgTDKpOLhqWgIWg6eySePDMw0gmLF9VwlPlPQ=")
d = {'M1': data}
xml = plistlib.dumps(d, fmt=plistlib.FMT_XML)
print(xml.decode())
