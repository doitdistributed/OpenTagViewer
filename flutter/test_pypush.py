import urllib.request
url = "https://raw.githubusercontent.com/JJTech0130/pypush/master/pypush_gsa_icloud.py"
try:
    code = urllib.request.urlopen(url).read().decode('utf-8')
    print(code)
except Exception as e:
    print(e)
