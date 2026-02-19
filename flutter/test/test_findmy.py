import sys
import os
sys.path.insert(0, '/Users/doitdistributed/Documents/code/blabs/OpenTagViewer/flutter/temp_findmy')

import srp._pysrp as srp
import hashlib
import binascii
import base64

salt = base64.b64decode("Ewmf0X1rn5k+Ir9QSLhMpw==")
B_bytes = base64.b64decode("F2v1+7Wps2nOAUSdqRzhPBa0xSc1TPwffWsCJ5pfutNX8ktjh41XhJD1zlVKhcHvGMaZnpM/N6mHG0PP2anoF42qQW8y7RSDzgM2f3ZclLVy0Oda4ZqK7l8vo7EB1Vlf1/R3Wy7n7EJFtKmUbxJ1ZiOXWfz/86cd0WNX0ORsB4V2dCl6v1rX3UM61kKIMSspBCOizrMVL+/9Gwh3rXuCCu+SNY2qFc6vzLPexMGb3qXxeiu1uUEaoJmTuU9HogRU8DyqYSCvx1RXC3JgYVR3TS3m5lvyZxnXCb1A9fNEJozmZA8lKEzgYeEFXrKvfVz4om+MZjNCHF9+PZBqkNakSA==")
B = int.from_bytes(B_bytes, 'big')

# We can mock the user details but we don't have the exact password from the user's log.
# BUT wait! M1 calculation is deterministic if we have the password.
# From the logs we see: M1 sent = rB31zgBgTDKpOLhqWgIWg6eySePDMw0gmLF9VwlPlPQ=
M1_sent = base64.b64decode("rB31zgBgTDKpOLhqWgIWg6eySePDMw0gmLF9VwlPlPQ=")
print(f"M1_sent_len: {len(M1_sent)}")
print(f"M1_sent_hex: {binascii.hexlify(M1_sent).decode()}")

# If A2k length is wrong, maybe the server rejects it.
A2k_b64 = "XZh9gUISPO7UPwKxJHn+uD36SzMP6idtdW0YGz9c3GDrzOsvy3lWDE84eptAQS3MGlN6pGpNOZQhP9uNPy8LcoPjVHHMaNNLWQ/jIb+pvgw7nBJoH0rtv1oOnxNOemCj2NDQD63hrK78CedpvEVL+oQVSj2qOoyrf8JhQLuhgVpAu5IlmaLdYJ2nSs4ls3vrHF3RGEHdK22yats6Kgql7JxdqxbTy7JwKmiKsAPRqUe0E/S1CyQGRQTng95b4FaUSC3x/R+xBNjH42vqaDnoAtx1LVDMZ7p8Wa9SUvooSMlQrSHPc2FcrMImhhakbe02Krqp5cDtDBDbEFk="
A2k = base64.b64decode(A2k_b64)
print(f"A2k length: {len(A2k)}")
print(f"A2k hex: {binascii.hexlify(A2k).decode()}")
