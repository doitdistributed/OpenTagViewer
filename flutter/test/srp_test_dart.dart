import 'dart:convert';
import 'dart:typed_data';
import 'package:opentagviewer/services/srp/srp_helper.dart';

void main() {
  final helper = SrpHelper();
  
  // Use exact same values as Python test
  final username = 'bb@inf-ing.com';
  final password = 'TestPassword123';
  final a = BigInt.parse('99fd17553ce9d5a14b694ed20de2284ad50cd3eee8a732093fdcd217c82b0d34', radix: 16);
  final A = helper.calculateA(a);
  
  // salt = base64.b64decode("Ewmf0X1rn5k+Ir9QSLhMpw==")
  final salt = base64Decode("Ewmf0X1rn5k+Ir9QSLhMpw==");
  
  // B from Python test
  final B = SrpHelper.bytesToBigInt(base64Decode("NhVUBJq1NRtHn1SNWLpzwikd9KrI5xSw/xvnotan+WikBsGZ/QXsOVUu807ksFh079LQJ0gtaE4+2d58qWVGgYeRu/tkn6rC4LJHwkmhCFg3YROfEKiR5zcCwaN99/NK7yvEqGSBP5Bbw737PhIdsMRgOZ2qnOWTTubkShT/iG94m0EtfeplwTo3JLgJrVKLodF1jLKK6JWRjMpIo9/XWTplNydOiin97RFOOwDSCLoRRCXLfCnkSGdq5Dz4KgL+pKia+D7sP2lrlbeWKubid8qKf7gg1IA01QO8EBcohAreo52JF8mn8lc1HmjLpjmfYh/wSnKZLBNPfRW9caPKDg=="));
  final iterations = 20408;
  
  final proofs = helper.calculateM1(
      username: username,
      salt: Uint8List.fromList(salt),
      B: B,
      a: a,
      A: A,
      password: password,
      protocol: 's2k', 
      iterations: iterations,
  );
  
  final M1 = proofs['M1'] as Uint8List;
  final K = proofs['K'] as Uint8List;
  final S = proofs['S'] as BigInt;
  final x = proofs['x'] as BigInt;
  
  print('--- DART OUTPUT ---');
  print('k: ${helper.k.toRadixString(16)}');
  print('x: ${x.toRadixString(16)}');
  print('S: ${S.toRadixString(16)}');
  print("K: ${K.map((e) => e.toRadixString(16).padLeft(2, '0')).join()}");
  print("M1: ${M1.map((e) => e.toRadixString(16).padLeft(2, '0')).join()}");
  
  print('\n--- PYTHON REFERENCE ---');
  print('k: 4cba3fb2923e01fb263ddbbb185a01c131c638f2561942e437727e02ca3c266d');
  print('x: 3de69b55e9c9ed9144a9b59bebd0aa9db30478ab79713dfdaa34846c9d23f65b');
  print('S: 676436dfc97847244b03c0c81c5465c9d041ad8a4a57a478a9e93a6c53fd56d9e03d241c22975f16faad17a464e8a0cf9fab443b2fd0fdee10d18bc5cf81a2ee9889c7e86ccf230b59a8f3517b6722453931214615180058c38e00f63d7bf0f1e0785bb953f0fd5881a4af896a8e4ab1f710b9b9f9b9df3b808ab0d2b3da4b12ba0d629bbddabf2c0169b2406b803927799ac92efb7c26e6eca5bd22dc32574a827b9dc2074476d453f78d741624d775c418bb787056972ded166e53a311ac2a0f3e9764cd438483adcce58007cd13b5f1245683d02c8066479cc970c66017924259eb356439f094e52a43705213f5e7db61b986c1b586e2f128cf949feb5763');
  print('K: d4e17ec63ebc1288301c11cfe57d180c38c8cd8ee29f00db3b5c99cc5afe621f');
  print('M1: 982bb7a7fcf66e564be778d18b10d824feb593bfe65fa00187c790ace294cbc8');
}
