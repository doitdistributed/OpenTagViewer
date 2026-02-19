import sys
sys.path.insert(0, '/Users/doitdistributed/Documents/code/blabs/OpenTagViewer/flutter/temp_findmy')
import srp._pysrp as srp
import hashlib
import binascii
import base64

def check_m1():
    print("Testing manual key generation")
    salt = base64.b64decode("Ewmf0X1rn5k+Ir9QSLhMpw==")
    B_bytes = base64.b64decode("lOOUrAZfb/Fp0Gqu45LGPIp0dCLdaVRFDrthdI2UT5t5o/Tuier4MtD5GZAJqWiTammb0lLOfbZE4goZpcYo9XIogLRz++30IwZSG4pSrrowjnlUKbOPWB8qAi5UPqz7a3WpWUuYrEUNM7Uurdhi+YyeT2zTAp9y05LGP0N3s5QamhvuXh0OVY3iGBrU69IbV/ATz2Q3jI+wcCPVrvYV8awwe8aqGBzWckZ7ZrZnlQnlp3o3+Yi1qQJixeQE0YcEQtLU4RDj8p2j+LL+0yw1mCKbRHc8NXOvr/lIvOEpYctw3/tHcJ0LC990gUA1isXoeK6gU8hqQuueG+7dEW2b8g==")
    B = int.from_bytes(B_bytes, 'big')
    
    # Values from flutter app:
    a = int("ddd58e26f32af18cafbbfc30168dde2f79f652e8cfc1d120b04badc15e8942e3", 16)
    x = int("d8b9def69bb3038ffc58fdf15f5f75adccddbe08a27c6308cca1059e9988e9b7", 16)
    
    NG2048_N = srp.NG_2048[0]
    NG2048_g = srp.NG_2048[1]
    
    A = pow(NG2048_g, a, NG2048_N)
    
    # NG2048 = (N, g) where N is index 0 and g is index 1.
    
    u = srp.calculate_u(srp.SHA256, A, B)
    
    # Calculate S 
    # S = (B - k * g^x) ^ (a + ux)
    k = srp.calculate_k(srp.SHA256, NG2048_N, NG2048_g)
    
    S = pow(B - k * pow(NG2048_g, x, NG2048_N), a + (u * x), NG2048_N) % NG2048_N
    
    import struct
    def PAD(n):
        return n.to_bytes(251, 'big')

    m1 = srp.calculate_M1(srp.SHA256, NG2048_N, NG2048_g, b'bb@inf-ing.com', salt, A, PAD(B), S)
    K = srp.calculate_K(srp.SHA256, S)
    print(f"S:  {hex(S)}")
    print(f"K:  {binascii.hexlify(K).decode()}")
    print(f"M1: {binascii.hexlify(m1).decode()}")
    print("M1 From FLUTTER LOG: ")
    print("abe8963ab9bb695037c90cef274b74ac25a4962918e294f6149f2d71fdf36acd")

check_m1()
