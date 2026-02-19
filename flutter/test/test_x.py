import hashlib
import binascii

salt = b'salty_salty'
p_enc = b'pbkdf2_fake_output_1234567890123'

# Python PySRP logic:
# H(hash_class, salt, H( hash_class, username + six.b(':') + password ) )
# with username = b''
inner = hashlib.sha256(b':' + p_enc).digest()
x_calc = hashlib.sha256(salt + inner).digest()

print(f"x = {binascii.hexlify(x_calc).decode()}")
