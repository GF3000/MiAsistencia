import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }

    throw UnsupportedError(
      'MiAsistencia is currently configured for Flutter Web only on '
      '${defaultTargetPlatform.name}.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBEshq_2QERbVgPFUWQ2zVl9dA5MJnE6XM',
    appId: '1:903834862577:web:724067d84d1936c23a7a50',
    messagingSenderId: '903834862577',
    projectId: 'mi-asistencia-c8854',
    authDomain: 'mi-asistencia-c8854.firebaseapp.com',
    storageBucket: 'mi-asistencia-c8854.firebasestorage.app',
    measurementId: 'G-KZHGN0SYD1',
  );
}
