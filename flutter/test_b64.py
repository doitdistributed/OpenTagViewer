import base64
import binascii

salt_b64 = "Ewmf0X1rn5k+Ir9QSLhMpw=="
salt_bytes = base64.b64decode(salt_b64)
print(f"salt hex: {binascii.hexlify(salt_bytes).decode()}")

b_b64 = "F2v1+7Wps2nOAUSdqRzhPBa0xSc1TPwffWsCJ5pfutNX8ktjh41XhJD1zlVKhcHvGMaZnpM/N6mHG0PP2anoF42qQW8y7RSDzgM2f3ZclLVy0Oda4ZqK7l8vo7EB1Vlf1/R3Wy7n7EJFtKmUbxJ1ZiOXWfz/86cd0WNX0ORsB4V2dCl6v1rX3UM61kKIMSspBCOizrMVL+/9Gwh3rXuCCu+SNY2qFc6vzLPexMGb3qXxeiu1uUEaoJmTuU9HogRU8DyqYSCvx1RXC3JgYVR3TS3m5lvyZxnXCb1A9fNEJozmZA8lKEzgYeEFXrKvfVz4om+MZjNCHF9+PZBqkNakSA=="
b_bytes = base64.b64decode(b_b64)
print(f"B len: {len(b_bytes)}")
print(f"B hex: {binascii.hexlify(b_bytes).decode()}")
