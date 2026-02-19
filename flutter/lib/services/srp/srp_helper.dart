
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// Helper for SRP-6a protocol used by Apple (Grand Slam Authentication).
/// 
/// Matches FindMy.py's exact configuration:
///   srp.rfc5054_enable()   → pads A, B, g, N to 256 bytes before hashing
///   srp.no_username_in_x() → username is empty bytes in x computation
class SrpHelper {
    // PySrp 2048-bit Group Parameters (from srp/_pysrp.py _ng_const)
    static final BigInt N = BigInt.parse(
        'AC6BDB41324A9A9BF166DE5E1389582FAF72B6651987EE07FC3192943DB56050A37329CBB4'
        'A099ED8193E0757767A13DD52312AB4B03310DCD7F48A9DA04FD50E8083969EDB767B0CF60'
        '95179A163AB3661A05FBD5FAAAE82918A9962F0B93B855F97993EC975EEAA80D740ADBF4FF'
        '747359D041D5C33EA71D281E446B14773BCA97B43A23FB801676BD207A436C6481F1D2B907'
        '8717461A5B9D32E688F87748544523B524B0D57D5EA77A2775D2ECFA032CFBDBF52FB37861'
        '60279004E57AE6AF874E7303CE53299CCC041C7BC308D82A5698F3A8D0C38271AE35F8E9DB'
        'FBB694B5C803D89F7AE435DE236D525F54759B65E372FCD68EF20FA7111F9E4AFF73',
        radix: 16,
    );
  static final BigInt g = BigInt.two;
  final Digest _digest = SHA256Digest();

  // Width of N in bytes (256 for 2048-bit). Used for RFC5054 padding.
  static final int _nWidth = bigIntToBytes(N).length; // = 256 bytes

  // "k" parameter: k = H(PAD(N) | PAD(g))
  // With rfc5054_enable(), H() pads each arg to width=len(N) bytes.
  late final BigInt k;

  SrpHelper() {
    k = _calculateK();
  }

  /// Calculates A = g^a % N
  BigInt calculateA(BigInt a) {
    return g.modPow(a, N);
  }

  /// Helper to hash multiple byte arrays: H(A | B | C ...)
  Uint8List hash(List<Uint8List> inputs) {
    _digest.reset();
    for (final input in inputs) {
      _digest.update(input, 0, input.length);
    }
    final output = Uint8List(_digest.digestSize);
    _digest.doFinal(output, 0);
    return output;
  }
  
  Uint8List hashBigInt(BigInt val) {
    return hash([bigIntToBytes(val)]);
  }

  /// Calculates k = H(PAD(N) | PAD(g))
  /// With rfc5054_enable(), both N and g are padded to len(N)=256 bytes.
  BigInt _calculateK() {
    // H(hash_class, N, g, width=len(long_to_bytes(N)))
    // → pads N and g to _nWidth bytes each
    final nPadded = bigIntToBytesPadded(N, _nWidth);
    final gPadded = bigIntToBytesPadded(g, _nWidth);
    final kBytes = hash([nPadded, gPadded]);
    return bytesToBigInt(kBytes);  
  }

  /// Converts BigInt to byte array (big endian), minimal length
  static Uint8List bigIntToBytes(BigInt number) {
    var hex = number.toRadixString(16);
    if (hex.length % 2 != 0) hex = '0$hex';
    final len = hex.length ~/ 2;
    final bytes = Uint8List(len);
    for (int i = 0; i < len; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  /// Converts BigInt to byte array (big endian) with specific length padding (left zero pad)
  static Uint8List bigIntToBytesPadded(BigInt number, int length) {
    final rawBytes = bigIntToBytes(number);
    if (rawBytes.length >= length) return rawBytes;
    final bytes = Uint8List(length);
    final offset = length - rawBytes.length;
    for (int i = 0; i < rawBytes.length; i++) {
        bytes[offset + i] = rawBytes[i];
    }
    return bytes;
  }
  
  static BigInt bytesToBigInt(Uint8List bytes) {
    var hex = '';
    for (var b in bytes) {
      hex += b.toRadixString(16).padLeft(2, '0');
    }
    if (hex.isEmpty) return BigInt.zero;
    return BigInt.parse(hex, radix: 16);
  }

  /// Generates a random ephemeral private key 'a' (256 bytes like PySrp)
  BigInt generateRandomA() {
    final random = Random.secure();
    final bytes = Uint8List(256); // PySrp uses get_random_of_length(256)
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }
    // Ensure top bit is set (like PySrp: get_random_of_length sets top bit)
    bytes[0] |= 0x80;
    return bytesToBigInt(bytes);
  }
  
  /// Client computes Session Key Premaster Secret 'S' and Proof 'M1'
  ///
  /// Matches FindMy.py with srp.rfc5054_enable() and srp.no_username_in_x():
  ///
  /// u = H(PAD(A, 256) | PAD(B, 256))    ← rfc5054: pad A and B to N-width
  /// x computed with username=b''          ← no_username_in_x()
  /// k = H(PAD(N, 256) | PAD(g, 256))    ← rfc5054: pad g to N-width
  /// HNxorg: hg = H(PAD(g, len(N)))       ← rfc5054: pad g for XOR
  /// M1 uses unpadded A and B              ← calculate_M uses long_to_bytes (unpadded)
  ///
  /// Returns { 'S': BigInt, 'M1': Uint8List, 'K': Uint8List }
  Map<String, dynamic> calculateM1({
    required String username, // I (included in plist `u` field but NOT in x hash)
    required Uint8List salt,     // s
    required BigInt B,        // Server Public Key
    required BigInt a,        // Client Private Key
    required BigInt A,        // Client Public Key
    required String password, // P
    String protocol = 's2k',   // 's2k' or 's2k_fo'
    int? iterations,          // PBKDF2 iterations (from server response `i`)
  }) {
    // 1. Calculate u = H(PAD(A, 256) | PAD(B, 256))
    // rfc5054_enable(): H() pads A and B to width=len(long_to_bytes(N))=256 bytes
    final APadded = bigIntToBytesPadded(A, _nWidth);
    final BPadded = bigIntToBytesPadded(B, _nWidth);
    final uBytes = hash([APadded, BPadded]);
    final u = bytesToBigInt(uBytes);
    
    // Safety check: u != 0
    if (u == BigInt.zero) throw Exception('SRP Safety Check Failed: u == 0');

    // 2. Calculate x
    // With no_username_in_x(): gen_x uses username=b'' (empty bytes)
    // gen_x: x = H(salt | H(username_b + b':' + password_bytes))
    //   → username_b = b'' (due to no_username_in_x)
    //   → password_bytes = encryptedPassword (bytes from PBKDF2)
    //
    // FindMy.py: encrypt_password(password, salt, iterations, protocol)
    //   p = SHA256(password.encode('utf-8')).digest()
    //   if s2k_fo: p = p.hex().encode('utf-8')
    //   encryptedPassword = PBKDF2HMAC(SHA256, 32, salt, iterations).derive(p)
    // Then: usr.p = encryptedPassword
    
    BigInt x;
    if (iterations != null && iterations > 0) {
        final passwordBytes = Uint8List.fromList(utf8.encode(password));
        var p = hash([passwordBytes]); // SHA256(password_utf8)
        
        Uint8List pbkdf2Input;
        if (protocol == 's2k_fo') {
            // s2k_fo: p = sha256_digest.hex().encode('utf-8')
            final hexStr = p.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
            pbkdf2Input = Uint8List.fromList(utf8.encode(hexStr));
        } else {
            // s2k: use raw SHA256 digest bytes
            pbkdf2Input = p;
        }
        
        final mac = HMac(SHA256Digest(), 64);
        final gen = PBKDF2KeyDerivator(mac)
          ..init(Pbkdf2Parameters(salt, iterations, 32));
        
        final encryptedPassword = gen.process(pbkdf2Input);
        
        // gen_x with no_username_in_x(): username = b''
        // x = H(salt | H(b'' + b':' + encryptedPassword))
        final innerHash = hash([
            Uint8List(0),  // empty username (no_username_in_x)
            Uint8List.fromList(utf8.encode(':')),
            encryptedPassword
        ]);
        final xBytes = hash([salt, innerHash]);
        
        x = bytesToBigInt(xBytes);
    } else {
        // Non-PBKDF2 path: standard gen_x with no_username_in_x()
        // x = H(salt | H(b'' + b':' + password_utf8))
        final innerHash = hash([
            Uint8List(0), // empty username (no_username_in_x)
            Uint8List.fromList(utf8.encode(':')),
            Uint8List.fromList(utf8.encode(password))
        ]);
        final xBytes = hash([salt, innerHash]);
        x = bytesToBigInt(xBytes);
    }

    // 3. Calculate S = (B - k * g^x) ^ (a + u * x) % N
    final gx = g.modPow(x, N);
    final k_gx = (k * gx) % N;
    var base = (B - k_gx) % N;
    if (base < BigInt.zero) base += N;
    
    final exp = (a + u * x); // exponent is NOT reduced mod N
    final S = base.modPow(exp, N);
    
    // 4. Calculate K = H(S)
    // PySrp: hash_class(long_to_bytes(self.S)).digest()  — unpadded S
    final K = hash([bigIntToBytes(S)]);
    
    // 5. Calculate M1 = H( HNxorg | H(I) | s | A | B | K )
    //
    // HNxorg with rfc5054_enable():
    //   bin_N = long_to_bytes(N)  → unpadded N bytes
    //   bin_g = long_to_bytes(g)  → unpadded g bytes
    //   padding = len(bin_N) - len(bin_g)  → pad g on the left
    //   hN = hash(bin_N)
    //   hg = hash(b'\0' * padding + bin_g)
    //   result = hN XOR hg
    //
    // Note: calculate_M uses long_to_bytes(A) and long_to_bytes(B) — UNPADDED!
    
    final nBytes = bigIntToBytes(N);   // N unpadded (~256 bytes)
    
    // Pad g to len(N) bytes for hg computation (rfc5054 HNxorg padding)
    final gPaddedForXor = bigIntToBytesPadded(g, nBytes.length);
    
    final hN = hash([nBytes]);
    final hg = hash([gPaddedForXor]);
    final hXor = Uint8List(hN.length);
    for(int i = 0; i < hN.length; i++) {
        hXor[i] = hN[i] ^ hg[i];
    }
    
    // calculate_M: h.update(hash_class(I).digest()) — uses I (username), not b''
    // NOTE: Even with no_username_in_x, the username IS included in M1!
    // The no_username_in_x only affects the x computation.
    final hI = hash([Uint8List.fromList(utf8.encode(username))]);
    
    // calculate_M uses long_to_bytes(A) and long_to_bytes(B) — unpadded
    final ABytes = bigIntToBytes(A);
    final BBytes = bigIntToBytes(B);
    
    final M1 = hash([
        hXor,
        hI,
        salt,
        ABytes,   // unpadded (calculate_M uses long_to_bytes)
        BBytes,   // unpadded
        K
    ]);
    
    print('[calculateM1] a: ${a.toRadixString(16)}');
    print('[calculateM1] A: ${A.toRadixString(16)}');
    print('[calculateM1] x (PBKDF2): ${x.toRadixString(16)}');
    print('[calculateM1] u: ${u.toRadixString(16)}');
    print('[calculateM1] S: ${S.toRadixString(16)}');
    print('[calculateM1] K: ${bytesToBigInt(K).toRadixString(16)}');
    print('[calculateM1] M1: ${bytesToBigInt(M1).toRadixString(16)}');

    return {
        'S': S,
        'M1': M1,
        'K': K,
        'x': x,
    };
  }
  
  /// Client validates server proof M2
  /// M2 = H(A | M1 | K)  — using unpadded A (calculate_H_AMK uses long_to_bytes)
  bool verifyM2({
    required BigInt A,
    required Uint8List M1,
    required Uint8List K,
    required Uint8List serverM2,
  }) {
      // PySrp calculate_H_AMK: h.update(long_to_bytes(A)) — unpadded
      final expectedM2 = hash([
          bigIntToBytes(A), // unpadded
          M1,
          K
      ]);
      
      if (expectedM2.length != serverM2.length) return false;
      var result = 0;
      for (int i = 0; i < expectedM2.length; i++) {
          result |= expectedM2[i] ^ serverM2[i];
      }
      return result == 0;
  }
}
