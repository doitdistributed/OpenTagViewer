import sys
import os

try:
    import srp._pysrp as srp
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "srp"])
    import srp._pysrp as srp

import hashlib
import binascii
try:
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "cryptography"])
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

def encrypt_password(password: str, salt: bytes, iterations: int, protocol: str) -> bytes:
    p = hashlib.sha256(password.encode("utf-8")).digest()
    if protocol == "s2k_fo":
        p = p.hex().encode("utf-8")
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt,
        iterations=iterations,
    )
    return kdf.derive(p)

srp.rfc5054_enable()
srp.no_username_in_x()

password = "Password123!"
salt = b'salty_salty'
iterations = 20000
protocol = 's2k'

p_enc = encrypt_password(password, salt, iterations, protocol)

usr = srp.User('test@example.com', b'', hash_alg=srp.SHA256, ng_type=srp.NG_2048)
usr.I = b'test@example.com' # or it's not used in x 
usr.p = p_enc   

x_calc_no_username = hashlib.sha256(salt + hashlib.sha256(p_enc).digest()).digest()
x_calc_username = hashlib.sha256(salt + hashlib.sha256(usr.I + b':' + p_enc).digest()).digest()

print(f"p_enc = {binascii.hexlify(p_enc).decode()}")
print(f"x_calc_no_username = {binascii.hexlify(x_calc_no_username).decode()}")
print(f"x_calc_username = {binascii.hexlify(x_calc_username).decode()}")

a = 0x1234567890abcdef
import struct
def int_to_bytes(n):
    return n.to_bytes((n.bit_length() + 7) // 8, 'big')

usr.a = srp.bytes_to_long(int_to_bytes(a))
usr.A = pow(srp.NG_2048[0], usr.a, srp.NG_2048[1])
B = 0x12345678

m1 = usr.process_challenge(salt, int_to_bytes(B))
print(f"A = {binascii.hexlify(int_to_bytes(usr.A)).decode()}")
print(f"M1 = {binascii.hexlify(m1).decode()}")

