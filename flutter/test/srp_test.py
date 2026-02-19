import hashlib
import binascii

N_hex = "AC6BDB41324A9A9BF166DE5E1389582FAF72B6651987EE07FC3192943DB56050A37329CBB4A099ED41985F60BED4DD54A6273ACAC669039B951909EA042287617D292881D18AC3710153D86C3C4819E63FE13BA4FE9323D9004F34A6006456247963A1F4504104B8C11750EE45831911D00898553D072CA10425C5784C8F5B8FE8CD9500A7D43909774619E256C87FB08A4D2E555C099D079BC8C33E4DFA50AE2237887259067C19658E00996B11046A9287E85B2467E0A8C9B501B0576A96E8A85871221D7CE031664C7270415A5B64627885F17F9D5E227656608933256038A639B0A33703E6C0C4679717D5F76288AC2423E116298516104281"
N_BYTES = binascii.unhexlify(N_hex)
N_LEN = len(N_BYTES)
N = int.from_bytes(N_BYTES, 'big')

G_BYTES = b'\x02'
g = 2

k = int.from_bytes(hashlib.sha256(N_BYTES + G_BYTES).digest(), "big")

username = "test@example.com"
password = "Password123!"
a = 0x1234567890abcdef
A = pow(g, a, N)
salt_b = b'salty_salty'
B = 0x12345678

iterations = 20000

def PAD(n):
    return n.to_bytes(N_LEN, 'big')

A_pad = PAD(A)
B_pad = PAD(B)
u = int.from_bytes(hashlib.sha256(A_pad + B_pad).digest(), 'big')

p_hash = hashlib.sha256(password.encode("utf-8")).digest()
x_bytes_pbkdf2 = hashlib.pbkdf2_hmac('sha256', p_hash, salt_b, iterations, 32)
# DOUBLE HASH matching PySrp
x_bytes = hashlib.sha256(salt_b + hashlib.sha256(b':' + x_bytes_pbkdf2).digest()).digest()

x = int.from_bytes(x_bytes, 'big')

gx = pow(g, x, N)
kgx = (k * gx) % N
val3 = (B - kgx) % N
if val3 < 0: val3 += N
S = pow(val3, a + u * x, N)

K = hashlib.sha256(PAD(S)).digest()

hN = hashlib.sha256(N_BYTES).digest()
hg = hashlib.sha256(G_BYTES).digest()
hXor = bytes([n ^ g_byte for n, g_byte in zip(hN, hg)])
hI = hashlib.sha256(username.encode()).digest()

M1 = hashlib.sha256(hXor + hI + salt_b + A_pad + B_pad + K).digest()

print('--- PYTHON PYPUSH LOGIC (PAD TO len(N_BYTES)) ---')
print(f'k: {k:x}')
print(f'x: {x:x}')
print(f'S: {S:x}')
print(f'K: {binascii.hexlify(K).decode()}')
print(f'M1: {binascii.hexlify(M1).decode()}')
