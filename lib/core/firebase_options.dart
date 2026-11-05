import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => ios,
      TargetPlatform.android => android,
      _ => android,
    };
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDV6-rfORNNXLHXWCh2FwRMAf1Vp-cJ5KA',
    appId: '1:221688035966:android:50f747230496c26d03f62f',
    messagingSenderId: '221688035966',
    projectId: 'ems-app-ea702',
    storageBucket: 'ems-app-ea702.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAhScFb2CTHR4qdZossWlDcJN6rJWy9Y2k',
    appId: '1:221688035966:ios:8bd43308fd93613a03f62f',
    messagingSenderId: '221688035966',
    projectId: 'ems-app-ea702',
    storageBucket: 'ems-app-ea702.firebasestorage.app',
    iosBundleId: 'com.neosolution.ems',
  );
}
