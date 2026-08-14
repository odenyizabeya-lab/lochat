import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Builds a [CallRtcController] for a call of [isVideo].
typedef CallRtcControllerFactory = CallRtcController Function({
  required bool isVideo,
});

/// Contract for the WebRTC media plane of a call.
///
/// The UI depends only on this interface; the production implementation is
/// [DeviceCallRtcController] (flutter_webrtc). Tests inject a fake that never
/// touches platform channels.
abstract interface class CallRtcController {
  /// Creates the peer connection and captures local media (audio always,
  /// video only for video calls). Safe to call once.
  Future<void> initialize();

  /// Creates the caller's SDP offer (also set as the local description).
  Future<RTCSessionDescription> createOffer();

  /// Applies the caller's offer (callee side) and returns the answer.
  Future<RTCSessionDescription> createAnswer(RTCSessionDescription offer);

  /// Applies the callee's answer (caller side).
  Future<void> setRemoteDescription(RTCSessionDescription answer);

  /// Adds a remote ICE candidate gathered from the signaling channel.
  Future<void> addIceCandidate(RTCIceCandidate candidate);

  /// Local ICE candidates to forward to the peer over signaling.
  Stream<RTCIceCandidate> get localCandidates;

  /// Emits once the peer connection reaches the connected state.
  Stream<void> get connected;

  /// Mutes/unmutes the local audio track. [muted] reflects the state.
  Future<void> toggleMute();

  bool get muted;

  /// Toggles the local camera (video calls only). [cameraEnabled] reflects it.
  Future<void> toggleCamera();

  bool get cameraEnabled;

  /// Switches the local camera between front and rear (video calls only).
  Future<void> switchCamera();

  /// Preview of the local camera, or null on audio calls.
  Widget? get localView;

  /// The remote peer's video, or null until a remote track arrives.
  Widget? get remoteView;

  /// Releases the peer connection, streams, and renderers.
  Future<void> dispose();
}
