import 'dart:async';

import 'package:flutter/foundation.dart';

import 'call_session_controller.dart';
import 'rtc/call_rtc_controller.dart';
import 'signaling/call_signaling_service.dart';

/// App-wide call services: the Firestore [signaling] service, the WebRTC
/// [rtcFactory], and the single [activeSession] so a new call replaces the
/// previous one.
class CallController extends ChangeNotifier {
  CallController({
    required this.signaling,
    required this.rtcFactory,
  });

  final CallSignalingService signaling;
  final CallRtcControllerFactory rtcFactory;

  CallSessionController? _active;

  /// The in-progress session (outgoing or incoming), if any.
  CallSessionController? get activeSession => _active;

  /// Builds the session for an outgoing call. The session is connected via
  /// [CallSessionController.startOutgoing] by the call screen right after
  /// navigation, so the ringing UI appears immediately.
  CallSessionController beginCall({required String myUid}) => _create(myUid);

  /// Prepares the session for an incoming ringing call (connects on accept).
  CallSessionController prepareIncoming({
    required String myUid,
    required String callId,
  }) {
    final CallSessionController session = _create(myUid);
    unawaited(session.prepareIncoming(callId: callId));
    return session;
  }

  CallSessionController _create(String myUid) {
    _active?.dispose();
    final CallSessionController session = CallSessionController(
      signaling: signaling,
      rtcFactory: rtcFactory,
      myUid: myUid,
    );
    _active = session;
    notifyListeners();
    return session;
  }

  /// Clears [session] from the app state when its screen closes.
  void clearSession(CallSessionController session) {
    if (identical(_active, session)) {
      _active = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _active?.dispose();
    _active = null;
    super.dispose();
  }
}
