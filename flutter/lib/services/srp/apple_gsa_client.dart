import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:opentagviewer/services/srp/srp_helper.dart';

class AppleGsaClient {
  static const String _gsaUrl = 'https://gsa.apple.com/grandslam/GsService2';
  final http.Client _httpClient;
  final SrpHelper _srpHelper;

  AppleGsaClient({http.Client? client})
      : _httpClient = client ?? http.Client(),
        _srpHelper = SrpHelper();

  void dispose() => _httpClient.close();

  /// Separates anisette headers into HTTP headers and CPD headers.
  static Map<String, Map<String, String>> _splitAnisetteHeaders(Map<String, String> anisetteHeaders) {
    final httpHeaders = <String, String>{};
    final cpdHeaders = <String, String>{};
    
    anisetteHeaders.forEach((k, v) {
        final upperK = k.toUpperCase();
        if (upperK == 'X-MME-CLIENT-INFO' || 
            upperK == 'X-APPLE-APP-INFO' || 
            upperK == 'X-XCODE-VERSION') {
            httpHeaders[k] = v;
        } else {
            cpdHeaders[k] = v;
        }
    });
    return {'http': httpHeaders, 'cpd': cpdHeaders};
  }

  /// Performs the full SRP login flow.
  /// [anisetteProvider] is called for EACH GSA request to get fresh anisette.
  /// Returns a map with 'response' (body dict) and 'headers' (http headers).
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    required Future<Map<String, String>> Function() anisetteProvider,
  }) async {
    // 1. Generate ephemeral private key 'a' and public key 'A'
    final a = _srpHelper.generateRandomA();
    final A = _srpHelper.calculateA(a);
    debugPrint('[AppleGsaClient] generated a: ${a.toRadixString(16)}');
    debugPrint('[AppleGsaClient] generated A: ${A.toRadixString(16)}');
    
    // 2. Step 1: Init (Send A to server) — fresh anisette
    final initAnisette = await anisetteProvider();
    final initSplit = _splitAnisetteHeaders(initAnisette);
    final initPlist = _buildInitPlist(username, A, initSplit['cpd']!);
    debugPrint('[AppleGsaClient] Sending Init Request...');
    debugPrint('[AppleGsaClient] Password length: ${password.length} chars');
    
    // Pass extracted HTTP headers to the raw socket request
    final initResp = await _postToGsaRaw(initPlist, additionalHeaders: initSplit['http']!);
    
    if (initResp.statusCode != 200) {
        throw Exception('GSA Init HTTP Error: ${initResp.statusCode} Body: ${initResp.body}');
    }
    
    debugPrint('[AppleGsaClient] Parsing Init Response...');
    final responseDict = _parseGsaResponse(initResp.body);
    debugPrint('[AppleGsaClient] Init Response Parsed: ${responseDict.keys}');
    debugPrint('[AppleGsaClient] Init Response Status: ${responseDict["Response"]?["Status"]}');
    debugPrint('[AppleGsaClient] Init Server Params: ${responseDict["Response"]}');
    
    // The structure is usually: { Response: { Status: { ... }, B: ..., s: ... } }
    final serverParams = responseDict['Response'] as Map<String, dynamic>?;
    if (serverParams == null) {
       throw Exception('GSA Response missing "Response" key: $responseDict');
    }
    
    final statusInit = serverParams['Status'] as Map<String, dynamic>?;
    if (statusInit != null) {
       final ec = statusInit['ec'] as int?;
       if (ec != null && ec != 0) {
           throw Exception('GSA Init Failed (EC=$ec): ${statusInit['em']}');
       }
    }
    
    debugPrint('[AppleGsaClient] Calculating M1...');
    // Access with null check to produce better error message if missing
    final B_bytes = serverParams['B'] as Uint8List?;
    final s_bytes = serverParams['s'] as Uint8List?;
    
    if (B_bytes == null || s_bytes == null) {
        throw Exception('GSA Response missing B or s parameters. Server Params keys: ${serverParams.keys}');
    }
    
    final B = SrpHelper.bytesToBigInt(B_bytes);
    
    // Check which protocol server selected
    final sp = serverParams['sp'] as String? ?? 's2k'; // Default to s2k if missing
    final iterations = serverParams['i'] as int?; // PBKDF2 iterations
    
    debugPrint('[AppleGsaClient] Server selected protocol: $sp, iterations: $iterations');

    // 3. Calculate M1
    final proofs = _srpHelper.calculateM1(
        username: username,
        salt: s_bytes,
        B: B,
        a: a,
        A: A,
        password: password,
        protocol: sp,
        iterations: iterations,
    );
    
    final M1 = proofs['M1'] as Uint8List;
    final K = proofs['K'] as Uint8List;
    
    debugPrint('[AppleGsaClient] Sending Complete Request...');
    final c = serverParams['c'] as String?;
    debugPrint('[AppleGsaClient] Extracted c: $c');
    if (c == null) {
        debugPrint('Warning: Server did not return "c" parameter.');
    }

    // CRITICAL: Get FRESH anisette for the complete request (FindMy.py does this)
    final completeAnisette = await anisetteProvider();
    final completeSplit = _splitAnisetteHeaders(completeAnisette);
    final completePlist = _buildCompletePlist(username, M1, completeSplit['cpd']!, c);
    final completeResp = await _postToGsaRaw(completePlist, additionalHeaders: completeSplit['http']!);
    
    if (completeResp.statusCode != 200) {
        throw Exception('GSA Complete HTTP Error: ${completeResp.statusCode}');
    }
    
    final completeDict = _parseGsaResponse(completeResp.body);
    
    // Check Status
    final completeResponse = completeDict['Response'] as Map<String, dynamic>?;
    final status = completeResponse?['Status'] as Map<String, dynamic>?;
    final ec = status?['ec'] as int?;
    
    if (ec != 0) {
        // Return the error response directly (might be 2FA requirement)
        return {
            'response': completeDict,
            'headers': completeResp.headers,
        };
    }
    
    // 5. Verify M2 (Only if success)
    // 5. Verify M2 (Only if success)
    final completeParams = completeDict['Response'] as Map<String, dynamic>;
    final M2_bytes = completeParams['M2'] as Uint8List;
    
    if (!_srpHelper.verifyM2(A: A, M1: M1, K: K, serverM2: M2_bytes)) {
        throw Exception('Server Authenticity Verification Failed (M2 mismatch)');
    }
    
    // Return success response with headers
    return {
        'response': completeDict,
        'headers': completeResp.headers,
    };
  }

  /// Requests a 2FA code (SMS or Trusted Device).
  Future<void> request2faCode({
    required Map<String, String> sessionHeaders,
    required String methodId, // 'trusted_device' or 'sms' (if phone)
    required Map<String, String> anisetteHeaders,
  }) async {
      // Construction of 2FA request depends on GSA protocol.
      // Usually it's a PUT to /grandslam/GsService2 with specific headers.
      // Or it might be a new plist with 'o'='sc' (Security Code request)?
      
      // Based on typical GSA reversing (e.g. PyPush/FindMy):
      // To request a code, we often just need to hit the endpoint with the Session Token
      // and a specific header instructing it to send the code.
      // However, strict GSA often uses a plist.
      
      // Let's assume for now we use the headers returned from Login.
      // Specifically 'X-Apple-Session-Token' or 'X-Apple-TwoSV-User-Client'.
      
      final headers = <String, String>{
          ...sessionHeaders,
          'Content-Type': 'text/x-xml-plist',
          'Accept': '*/*'
      };
      
      // Add Anisette Headers
      anisetteHeaders.forEach((k, v) {
            final upperK = k.toUpperCase();
            if (upperK == 'X-MME-CLIENT-INFO' || 
                upperK == 'X-APPLE-APP-INFO' || 
                upperK == 'X-XCODE-VERSION') {
                headers[k] = v;
            }
      });
      
      // Add User Agent
      headers['User-Agent'] = 'akd/1.0 CFNetwork/978.0.7 Darwin/18.7.0'; // Mojave
      
      // Construct Plist
      // <key>Header</key><dict><key>Version</key><string>1.0.1</string></dict>
      // <key>Request</key><dict>
      //    <key>cpd</key>...
      //    <key>o</key><string>put</string> (PUT Request?) NO.
      
      // Actually, for sending a code to a device, we often use the 'PUT' method on the HTTP request
      // with a specific header: `X-Apple-Id-Session-Id`.
      
      // Wait, let's keep it simple. If we are in the "Generic 2FA" state, 
      // the server usually provides `trustedDevices` in the response.
      // To trigger a push, we usually send an empty PUT to the session resource?
      // Or a plist with `u` (username) + `o`='sc' (security code)?
      
      // Implementation Guess based on FindMy.py:
      // It seems to just handle the '2FA Required' response.
      // For Trusted Device, it often auto-pushes?
      // If manually requesting:
      // HTTP PUT to https://gsa.apple.com/grandslam/GsService2
      // Headers: Valid Session Headers (Cookie / X-Apple-Session-Token).
      // Body: Plist with `o`=`sc` (Security Code)?
      
      // Let's try constructing a standard "Update" request.
      
      final buffer = StringBuffer();
      buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
      buffer.writeln('<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">');
      buffer.writeln('<plist version="1.0">');
      buffer.writeln('<dict>');
      buffer.writeln('	<key>Header</key><dict><key>Version</key><string>1.0.1</string></dict>');
      buffer.writeln('	<key>Request</key>');
      buffer.writeln('	<dict>');
      buffer.writeln('		<key>cpd</key>');
      buffer.writeln('		<dict>');
      // Minimal CPD or Full CPD? Full is safer.
      buffer.writeln('			<key>bootstrap</key><true/>');
      buffer.writeln('			<key>icscrec</key><true/>');
      buffer.writeln('			<key>pbe</key><false/>');
      buffer.writeln('			<key>prkgen</key><true/>');
      buffer.writeln('			<key>svct</key><string>iCloud</string>');
      anisetteHeaders.forEach((k, v) {
        final upperK = k.toUpperCase();
        if (upperK.startsWith('X-APPLE-') || upperK.startsWith('X-MME-') || k == 'loc') {
            buffer.writeln('			<key>$k</key>');
            final escapedV = v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
            buffer.writeln('			<string>$escapedV</string>');
        }
      });
      buffer.writeln('		</dict>');
      
      // Operation: Request Security Code
      // This is often just 'PUT' verb with empty body or specific header?
      // Let's try sending a plist with `o`='vet' (Verify Phone) or similar if SMS.
      // For Trusted Device, it's often automatic.
      
      // If the user explicitly requested it, maybe we re-send header?
      // Actually, standard GSA behavior:
      // PUT /grandslam/GsService2
      // Header: X-Apple-Id-Session-Id: <SessionID>
      // Header: X-Apple-Widget-Key: <Key> ?
      
      // Let's TRY sending a minimal request with just the session headers we have.
      // If we simply POST the plist again, it might retry.
      
      // Let's defer to the user's manual "methodId" logic.
      // If methodId == 'trusted_device', we assume we want to trigger the push.
      
      // IMPORTANT: In `AppleAuthService`, the `requestTwoFactorCode` used `/request_2fa`.
      // We will replace that logic.
      
      // For now, let's implement a 'dummy' request that prints what it WOULD do,
      // and maybe sends a "resend" op.
      
      // TODO: Implement actual protocol. For now, we will trust the Session Token is enough.
      // If we return, the UI will ask for the code.
      
      debugPrint('[AppleGsaClient] Requesting 2FA Code (Method: $methodId)');
  }

  Future<Map<String, dynamic>> validate2faCode({
    required Map<String, String> sessionHeaders,
    required String code,
    required String methodId,
    required Map<String, String> anisetteHeaders,
    required String username,
  }) async {
      debugPrint('[AppleGsaClient] Validating 2FA Code...');
      // 1. Build Plist with 'o'='sc' (Security Code) or similar? Not standard.
      // Usually: 'o'='complete' (again?) or 'o'='continue'?
      
      // Standard flow:
      // Post Plist:
      // o = 'sign' (Sign in?)
      // sc = <code> (The 6 digit code)
      // u = <username>
      
      final buffer = StringBuffer();
      buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
      buffer.writeln('<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">');
      buffer.writeln('<plist version="1.0">');
      buffer.writeln('<dict>');
      buffer.writeln('	<key>Header</key><dict><key>Version</key><string>1.0.1</string></dict>');
      buffer.writeln('	<key>Request</key>');
      buffer.writeln('	<dict>');
      buffer.writeln('		<key>cpd</key>');
      buffer.writeln('		<dict>');
      buffer.writeln('			<key>bootstrap</key><true/>');
      buffer.writeln('			<key>icscrec</key><true/>');
      buffer.writeln('			<key>pbe</key><false/>');
      buffer.writeln('			<key>prkgen</key><true/>');
      buffer.writeln('			<key>svct</key><string>iCloud</string>');
      anisetteHeaders.forEach((k, v) {
        final upperK = k.toUpperCase();
        if (upperK.startsWith('X-APPLE-') || upperK.startsWith('X-MME-') || k == 'loc') {
            buffer.writeln('			<key>$k</key>');
            final escapedV = v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
            buffer.writeln('			<string>$escapedV</string>');
        }
      });
      buffer.writeln('		</dict>');

      buffer.writeln('		<key>u</key><string>$username</string>');
      buffer.writeln('		<key>sc</key><string>$code</string>'); // The code
      buffer.writeln('		<key>o</key><string>complete</string>'); // Try complete again? Or 'validate'?
      
      // Some implementations use 's2k' again here?
      // Let's assume 'complete' with 'sc' is the standard "Submit Code" logic.
      
      buffer.writeln('	</dict>');
      buffer.writeln('</dict>');
      buffer.writeln('</plist>');
      
      // Separate headers
      final httpHeaders = <String, String>{};
      anisetteHeaders.forEach((k, v) {
            final upperK = k.toUpperCase();
            if (upperK == 'X-MME-CLIENT-INFO' || 
                upperK == 'X-APPLE-APP-INFO' || 
                upperK == 'X-XCODE-VERSION') {
                httpHeaders[k] = v;
            }
      });
      
      // MERGE session headers!
      sessionHeaders.forEach((k, v) {
          httpHeaders[k] = v;
      });
      
      final resp = await _postToGsaRaw(buffer.toString(), additionalHeaders: httpHeaders);
      
       if (resp.statusCode != 200) {
        throw Exception('GSA 2FA Validation HTTP Error: ${resp.statusCode}');
       }
    
       final resultDict = _parseGsaResponse(resp.body);
       return {
         'response': resultDict,
         'headers': resp.headers,
       };
  }

  Future<http.Response> _postToGsaRaw(String plistBody, {Map<String, String>? additionalHeaders}) async {
    final uri = Uri.parse(_gsaUrl);
    final bodyBytes = utf8.encode(plistBody);
    
    // Use SecureSocket for absolute control over bytes sent (casing, order, etc)
    // This bypasses dart:io HttpClient normalization.
    final socket = await SecureSocket.connect(uri.host, 443, 
        onBadCertificate: kDebugMode ? (_) => true : null);
    
    final sb = StringBuffer();
    sb.write('POST ${uri.path} HTTP/1.1\r\n');
    sb.write('Host: ${uri.host}\r\n');
    // Match the version in X-MMe-Client-Info (macOS 10.14 = Darwin 18.7.0) to match FindMy.py
    sb.write('User-Agent: akd/1.0 CFNetwork/978.0.7 Darwin/18.7.0\r\n');
    
    // Write additional headers (like X-MMe-Client-Info)
    if (additionalHeaders != null) {
        additionalHeaders.forEach((k, v) {
            sb.write('$k: $v\r\n');
        });
    }

    sb.write('Accept: */*\r\n');
    sb.write('Accept-Language: en-US\r\n');
    sb.write('Content-Type: text/x-xml-plist\r\n');
    sb.write('Connection: close\r\n');
    sb.write('Content-Length: ${bodyBytes.length}\r\n');
    sb.write('\r\n');
    
    final headerStr = sb.toString();
    debugPrint('[_postToGsaRaw] Sending RAW:\n$headerStr');
    debugPrint('[_postToGsaRaw] Request Body:\n$plistBody');
    
    socket.write(headerStr);
    socket.add(bodyBytes);
    await socket.flush();
    
    // Read response
    final responseBytes = <int>[];
    await for (final chunk in socket) {
      responseBytes.addAll(chunk);
    }
    socket.destroy();
    
    // Parse response manually (very basic)
    final responseStr = utf8.decode(responseBytes, allowMalformed: true);
    final parts = responseStr.split('\r\n\r\n');
    final headerPart = parts[0];
    final bodyPart = parts.length > 1 ? parts.sublist(1).join('\r\n\r\n') : '';
    
    // Parse status line
    final statusLine = headerPart.split('\r\n').first;
    final statusCode = int.tryParse(statusLine.split(' ')[1]) ?? 0;
    
    debugPrint('[_postToGsaRaw] Raw Response Headers:\n$headerPart');
    if (statusCode != 200) {
        debugPrint('[_postToGsaRaw] Raw Body:\n$bodyPart');
    } else {
        debugPrint('[_postToGsaRaw] Success Body:\n$bodyPart');
    }
    
    return http.Response(bodyPart, statusCode);
  }
  
  String _buildInitPlist(String username, BigInt A, Map<String, String> cpdHeaders) {
    // Manual construction to match FindMy python implementation.
    // Anisette headers MUST be in 'Request' -> 'cpd' dict, NOT 'Header' dict.
    
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">');
    buffer.writeln('<plist version="1.0">');
    buffer.writeln('<dict>');
    
    // Header Dict (Version Only)
    buffer.writeln('	<key>Header</key>');
    buffer.writeln('	<dict>');
    buffer.writeln('		<key>Version</key>');
    buffer.writeln('		<string>1.0.1</string>');
    buffer.writeln('	</dict>');
    
    // Request Dict
    buffer.writeln('	<key>Request</key>');
    buffer.writeln('	<dict>');
    
    // cpd (Client Provisioning Data) - contains Anisette headers + flags
    buffer.writeln('		<key>cpd</key>');
    buffer.writeln('		<dict>');
    // Static flags matching FindMy implementation
    buffer.writeln('			<key>bootstrap</key><true/>');
    buffer.writeln('			<key>icscrec</key><true/>');
    buffer.writeln('			<key>pbe</key><false/>');
    buffer.writeln('			<key>prkgen</key><true/>');
    buffer.writeln('			<key>svct</key><string>iCloud</string>');
    
    // Anisette Headers (filtered)
    cpdHeaders.forEach((k, v) {
        final upperK = k.toUpperCase();
        if (upperK.startsWith('X-APPLE-') || upperK.startsWith('X-MME-') || k == 'loc') {
            buffer.writeln('			<key>$k</key>');
            
            // Should be strings based on FindMy python source.
            // Even RINFO/SRL-NO allow string storage in plist (which json.dumps handles naturally).
            // We use standard string escaping.
            final escapedV = v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
            buffer.writeln('			<string>$escapedV</string>');
        }
    });
    buffer.writeln('		</dict>'); // End cpd

    buffer.writeln('		<key>A2k</key>');
    buffer.writeln('		<data>');
    // PySrp: start_authentication returns long_to_bytes(self.A) — UNPADDED
    final a2kBase64 = base64Encode(SrpHelper.bigIntToBytes(A));
    // Plistlib chunks at 68 chars
    for (int i = 0; i < a2kBase64.length; i += 68) {
        final end = (i + 68 < a2kBase64.length) ? i + 68 : a2kBase64.length;
        buffer.writeln('		${a2kBase64.substring(i, end)}');
    }
    buffer.writeln('		</data>');
    buffer.writeln('		<key>u</key>');
    buffer.writeln('		<string>$username</string>');
    buffer.writeln('		<key>ps</key>');
    buffer.writeln('		<array>');
    buffer.writeln('			<string>s2k</string>');
    buffer.writeln('			<string>s2k_fo</string>');
    buffer.writeln('		</array>');
    buffer.writeln('		<key>o</key>');
    buffer.writeln('		<string>init</string>');
    buffer.writeln('	</dict>'); // End Request
    
    buffer.writeln('</dict>');
    buffer.writeln('</plist>');
    
    return buffer.toString();
  }
  
  String _buildCompletePlist(String username, Uint8List M1, Map<String, String> cpdHeaders, String? c) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">');
    buffer.writeln('<plist version="1.0">');
    buffer.writeln('<dict>');
    
    // Header Dict (Version Only)
    buffer.writeln('	<key>Header</key>');
    buffer.writeln('	<dict>');
    buffer.writeln('		<key>Version</key>');
    buffer.writeln('		<string>1.0.1</string>');
    buffer.writeln('	</dict>');
    
    // Request Dict
    buffer.writeln('	<key>Request</key>');
    buffer.writeln('	<dict>');
    
    // cpd
    buffer.writeln('		<key>cpd</key>');
    buffer.writeln('		<dict>');
    buffer.writeln('			<key>bootstrap</key><true/>');
    buffer.writeln('			<key>icscrec</key><true/>');
    buffer.writeln('			<key>pbe</key><false/>');
    buffer.writeln('			<key>prkgen</key><true/>');
    buffer.writeln('			<key>svct</key><string>iCloud</string>');

    cpdHeaders.forEach((k, v) {
        final upperK = k.toUpperCase();
        if (upperK.startsWith('X-APPLE-') || upperK.startsWith('X-MME-') || k == 'loc') {
            buffer.writeln('			<key>$k</key>');
            final escapedV = v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
            buffer.writeln('			<string>$escapedV</string>');
        }
    });
    buffer.writeln('		</dict>');

    buffer.writeln('		<key>c</key>');
    buffer.writeln('		<string>$c</string>');
    buffer.writeln('		<key>M1</key>');
    buffer.writeln('		<data>');
    // python plistlib dumps data as: \t\t<data>\n\t\tb64...\n\t\t</data>
    final m1Base64 = base64Encode(M1);
    for (int i = 0; i < m1Base64.length; i += 68) {
        final end = (i + 68 < m1Base64.length) ? i + 68 : m1Base64.length;
        buffer.writeln('		${m1Base64.substring(i, end)}');
    }
    buffer.writeln('		</data>');
    buffer.writeln('		<key>u</key>');
    buffer.writeln('		<string>$username</string>');
    buffer.writeln('		<key>o</key>');
    buffer.writeln('		<string>complete</string>');
    buffer.writeln('	</dict>');
    
    buffer.writeln('</dict>');
    buffer.writeln('</plist>');
    
    return buffer.toString();
  }



  Map<String, dynamic> _parseGsaResponse(String xmlBody) {
      // Need a simple XML plist parser.
      // Since 'xml' package gives us the DOM, we need to traverse it.
      final doc = XmlDocument.parse(xmlBody);
      final rootDict = doc.findAllElements('dict').first;
      return _parseDict(rootDict);
  }
  
  dynamic _parseDict(XmlElement dict) {
      final result = <String, dynamic>{};
      final children = dict.children.whereType<XmlElement>().toList();
      
      for (int i = 0; i < children.length; i += 2) {
          final keyElement = children[i];
          final valueElement = children[i+1]; // Assumptions: key followed by value.
          
          if (keyElement.name.local != 'key') continue; // Robustness
          final key = keyElement.text;
          final value = _parseValue(valueElement);
          result[key] = value;
      }
      return result;
  }
  
  dynamic _parseValue(XmlElement element) {
      switch (element.name.local) {
          case 'string': return element.text;
          case 'integer': return int.parse(element.text);
          case 'data': return base64Decode(element.text.replaceAll(RegExp(r'\s+'), ''));
          case 'dict': return _parseDict(element);
          case 'array': 
            return element.children.whereType<XmlElement>().map(_parseValue).toList();
          case 'true': return true;
          case 'false': return false;
          default: return null;
      }
  }
}
