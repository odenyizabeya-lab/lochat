import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'models/call.dart';
import 'rtc/call_rtc_controller.dart';
import 'signaling/call_signaling_service.dart';

/// Drives one call end to end: signaling, peer connection setup, ICE exchange,
/// and lifecycle transitions. Exposes [call] (live) and [rtc] for the UI and
/// notifies on every change so screens can react to status/connectivity.
class CallSessionController extends ChangeNotifier {
  CallSessionController({
    required this.signaling,
    required this.rtcFactory,
    required this.myUid,
  });

  final CallSignalingService signaling;
  final CallRtcControllerFactory rtcFactory;
  final String myUid;

  Call? _call;
  CallRtcController? _rtc;
  bool _outgoing = false;
  bool _failed = false;
  String? _failureMessage;
  Future<void>? _prepareFuture;

  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  bool _disposed = false;

  Call? get call => _call;
  CallRtcController? get rtc => _rtc;
  bool get outgoing => _outgoing;
  bool get failed => _failed;
  String? get failureMessage => _failureMessage;
  bool get isVideo => _call?.isVideo ?? false;
  bool get isConnected => _rtc != null;

  /// Starts an outgoing call: creates the document, gathers media, writes the
  /// offer, then waits for the answer and the peer's candidates.
  Future<void> startOutgoing({
    required String calleeUid,
    required String conversationId,
    required CallType type,
  }) async {
    _outgoing = true;
    try {
      final String callId = await signaling.createCall(
        callerUid: myUid,
        calleeUid: calleeUid,
        type: type,
        conversationId: conversationId,
      );
      final Call? created = await signaling.fetchCall(callId);
      if (created == null) throw StateError('Call document was not created.');
      _call = created;
      _watchCall(callId);
      notifyListeners();

      await _openRtc();
      final RTCSessionDescription offer = await _rtc!.createOffer();
      await signaling.writeOffer(callId, offer.sdp ?? '');
      await _listenForAnswer(callId);
      await _exchangeCandidates(callId);
    } catch (e) {
      _markFailed(e);
    }
  }

  /// Loads an incoming ringing call and waits for the user to accept.
  ///
  /// The returned future completes once the call row is loaded (or failed),
  /// so [acceptIncoming] can be awaited immediately after.
  Future<void> prepareIncoming({required String callId}) {
    _outgoing = false;
    final Future<void> future = _prepareIncoming(callId);
    _prepareFuture = future;
    return future;
  }

  Future<void> _prepareIncoming(String callId) async {
    try {
      final Call? call = await signaling.fetchCall(callId);
      if (call == null || call.isFinished) {
        _markFailed(StateError('This call is no longer available.'));
        return;
      }
      _call = call;
      _watchCall(callId);
      notifyListeners();
    } catch (e) {
      _markFailed(e);
    }
  }

  /// Accepts the incoming call: applies the offer, answers, and starts ICE.
  Future<void> acceptIncoming() async {
    await _prepareFuture;
    final Call? call = _call;
    if (call == null) return;
    try {
      final String? offerSdp = await signaling.fetchOffer(call.id);
      if (offerSdp == null || offerSdp.isEmpty) {
        throw StateError('The caller never sent an offer.');
      }
      await _openRtc();
      final RTCSessionDescription answer =
          await _rtc!.createAnswer(RTCSessionDescription(offerSdp, 'offer'));
      await signaling.acceptCall(call.id);
      await signaling.writeAnswer(call.id, answer.sdp ?? '');
      await _exchangeCandidates(call.id);
    } catch (e) {
      _markFailed(e);
    }
  }

  /// Declines the incoming call.
  Future<void> declineIncoming() async {
    final Call? call = _call;
    if (call == null) return;
    try {
      await signaling.declineCall(call.id);
    } on Exception {
      // The call may have ended already; the watch stream will reconcile.
    }
  }

  /// Hangs up an unanswered outgoing call (renders as missed for the peer).
  Future<void> cancelOutgoing() async {
    final Call? call = _call;
    if (call == null) return;
    try {
      await signaling.markMissed(call.id);
    } on Exception {
      // Ignored; the document watch keeps screens in sync either way.
    }
  }

  /// Hangs up an active call.
  Future<void> endCall() async {
    final Call? call = _call;
    if (call == null) return;
    try {
      await signaling.endCall(call.id, byUid: myUid);
    } on Exception {
      // Ignored; screens reconcile from the live call stream.
    }
  }

  Future<void> toggleMute() async {
    await _rtc?.toggleMute();
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    await _rtc?.toggleCamera();
    notifyListeners();
  }

  bool get muted => _rtc?.muted ?? false;
  bool get cameraEnabled => _rtc?.cameraEnabled ?? true;

  Future<void> _openRtc() async {
    if (_rtc != null) return;
    final CallRtcController rtc = rtcFactory(isVideo: _call?.isVideo ?? false);
    await rtc.initialize();
    _rtc = rtc;
    _subscriptions.add(rtc.localCandidates.listen((RTCIceCandidate candidate) {
      final Call? call = _call;
      final String candidateSdp = candidate.candidate ?? '';
      if (call == null || candidateSdp.isEmpty) return;
      unawaited(
        signaling
            .addCandidate(
              call.id,
              CallCandidate(
                senderUid: myUid,
                candidate: candidateSdp,
                sdpMid: candidate.sdpMid ?? '',
                sdpMLineIndex: candidate.sdpMLineIndex ?? 0,
              ),
            )
            .catchError((Object _) {
              // Candidate writes may fail while offline; the peer still has
              // the candidates that were written before the drop.
            }),
      );
    }));
    _subscriptions.add(rtc.connected.listen((_) => notifyListeners()));
    notifyListeners();
  }

  Future<void> _listenForAnswer(String callId) async {
    _subscriptions.add(
      signaling.watchAnswer(callId).listen(
        (String sdp) {
          if (sdp.isEmpty || _rtc == null) return;
          unawaited(
            _rtc!.setRemoteDescription(RTCSessionDescription(sdp, 'answer')),
          );
        },
        onError: (Object error) {
          // Transient realtime drop: the answer may already have been fetched
          // below, and the RTC session can proceed on trickled candidates.
        },
      ),
    );
    final String? existing = await signaling.fetchAnswer(callId);
    if (existing != null && existing.isNotEmpty && _rtc != null) {
      await _rtc!.setRemoteDescription(RTCSessionDescription(existing, 'answer'));
    }
  }

  Future<void> _exchangeCandidates(String callId) async {
    final CallRtcController? rtc = _rtc;
    if (rtc == null) return;
    _subscriptions.add(
      signaling
          .watchCandidates(callId, excludeSender: myUid)
          .listen(
            (CallCandidate candidate) {
              unawaited(
                rtc.addIceCandidate(
                  RTCIceCandidate(candidate.candidate, candidate.sdpMid, candidate.sdpMLineIndex),
                ),
              );
            },
            onError: (Object error) {
              // Transient realtime drop: existing candidates are fetched
              // below; only late trickled candidates are lost.
            },
          ),
    );
    final List<CallCandidate> existing =
        await signaling.fetchCandidates(callId, excludeSender: myUid);
    for (final CallCandidate candidate in existing) {
      await rtc.addIceCandidate(
        RTCIceCandidate(candidate.candidate, candidate.sdpMid, candidate.sdpMLineIndex),
      );
    }
  }

  Timer? _watchCallRetry;

  void _watchCall(String callId) {
    late final StreamSubscription<Call> sub;
    sub = signaling.watchCall(callId).listen(
      (Call call) {
        _call = call;
        notifyListeners();
      },
      onError: (Object error) {
        // Realtime channel errors tear the stream down; without a handler
        // this would surface as an unhandled async error. Re-subscribe
        // (debounced) so the session keeps tracking the call after a
        // transient drop.
        _subscriptions.remove(sub);
        _watchCallRetry ??= Timer(const Duration(seconds: 2), () {
          _watchCallRetry = null;
          if (_disposed) return;
          _watchCall(callId);
        });
      },
    );
    _subscriptions.add(sub);
  }

  void _markFailed(Object error) {
    _failed = true;
    _failureMessage = switch (error) {
      StateError stateError => stateError.message,
      _ => 'Call failed. Check your connection and try again.',
    };
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _watchCallRetry?.cancel();
    _watchCallRetry = null;
    for (final StreamSubscription<Object?> sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    unawaited(_rtc?.dispose());
    _rtc = null;
    super.dispose();
  }
}
