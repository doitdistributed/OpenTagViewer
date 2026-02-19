import srp._pysrp as srp
import hashlib
import binascii

p_enc = binascii.unhexlify("72922ef65bfcb044697ffc642eade7fdca78a17688cb04a29a073c66f568b201")
salt = binascii.unhexlify("13099fd17d6b9f993e22bf5048b84ca7")
B = int.from_bytes(binascii.unhexlify("176bf5fbb5a9b369ce01449da91ce13c16b4c527354cfc1f7d6b02279a5fbad357f24b63878d578490f5ce554a85c1ef18c6999e933f37a9871b43cfd9a9e8178daa416f32ed1483ce03367f765c94b572d0e75ae19a8aee5f2fa3b101d5595fd7f4775b2ee7ec4245b4a9946f127566239759fcfff3a71dd16357d0e46c07857674297abf5ad7dd433ad64288312b290423a2ceb3152fef2"), 'big')

srp.rfc5054_enable()
srp.no_username_in_x()

usr = srp.User('bb@inf-ing.com', b'', hash_alg=srp.SHA256, ng_type=srp.NG_2048)
usr.I = b'bb@inf-ing.com'
usr.p = p_enc   
a = int.from_bytes(binascii.unhexlify("8cdbb28ff3a404c0ec87c69931b0ed69542a220268a2bf6cb91e4aa9de2156eb"), 'big')

import struct
def PAD(n):
    return n.to_bytes(251, 'big')

usr.a = a
usr.A = pow(srp.NG_2048[0], a, srp.NG_2048[1])

m1 = usr.process_challenge(salt, PAD(B))

print(f"M1: {binascii.hexlify(m1).decode()}")
