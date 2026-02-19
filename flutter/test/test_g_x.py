import sys
sys.path.insert(0, '/Users/doitdistributed/Documents/code/blabs/OpenTagViewer/flutter/temp_findmy')
import srp._pysrp as srp
import hashlib
import binascii
import base64

def check_keys():
    print("Testing manual key generation")
    salt = base64.b64decode("Ewmf0X1rn5k+Ir9QSLhMpw==")
    B_bytes = base64.b64decode("gidwvJGQRTdzLY8XowVmK24ClLLfTmA29rM1gkeMnY2z0d/yQDtR4M/VE3RrigUmoMEM8hKqrEob+RZqaF+2BFrAwnM5TkbjyFKSZOJ56K4KIL5Q0WC+Cz9PrtEMjWJ5sO/6YtwU/X0qJpagiqbZgyFcp4H1ZSk+5+C7Y1/oHNEGbSV4ETPY+Zf2Ol2GmJcY/4SOSYmVe2iLnWNRA2eY4dPWNdhCh3epnHFS9ryGnrdq4m6uIKGezWIJLOA62A1iu2rOsxlgmMz810XsjXYiayohxioUUjbj+TVKnJJ1ZV7RjgEMv/GDhoWo3iAFkFQz+oiRa5rR5HbhedDaoSHWEQ==")
    A2k = base64.b64decode("nLhT3x820gySTwSWXRIvPwj0xDZWWzgxb48pFnTTcNcUyQ/e5pKx+WGBwgxTUnxuIvlXYSkR9cMDQkSML4CCIyzM7MHl7lxN6seZuaT6f2k0GCR+7I0J5W2BTtLf4/w6kqOdEQiZL9RjsQ1+rMVHckLP9w1nBckWukpe51y8TgjPSqsAgtHidmlgQx9P3czTo6I5qE9p4/KWuf3wUBhY2m+2cmwhwzXu1EZjQ9GYMVDBCPnFgLIKz7vDd/6bvrwzpDeogODt64LoHvDTn+3K5jpex1my3U2mcLFOuqH5ZipiqoepkQkwznBFZleOtbczNgSPdkMYjG0HYXo=")
    # Unfortunately we do not know `a` (the private ephemeral key) that generated this `A2k` from the flutter run.
    # Therefore, we CANNOT generate M1 in Python to compare with the given B and salt from the flutter run.
    
    # We MUST intercept `a` inside flutter when running it to compare.
print("We need `a` from the flutter side to test Python M1 generation")
check_keys()
