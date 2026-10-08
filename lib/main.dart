import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'firebase_options.dart';
import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Local testing against `firebase emulators:start --only auth,firestore`:
  // flutter run --dart-define=USE_FIREBASE_EMULATORS=true
  if (const bool.fromEnvironment('USE_FIREBASE_EMULATORS')) {
    await FirebaseAuth.instance.useAuthEmulator(
      '127.0.0.1',
      const int.fromEnvironment('AUTH_EMULATOR_PORT', defaultValue: 9099),
    );
    FirebaseFirestore.instance.useFirestoreEmulator(
      '127.0.0.1',
      const int.fromEnvironment('FIRESTORE_EMULATOR_PORT', defaultValue: 8080),
    );
  }
  runApp(const ProviderScope(child: MiAsistenciaApp()));
}
