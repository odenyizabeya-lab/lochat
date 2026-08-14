import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import 'call_rtc_controller.dart';

/// Production [CallRtcController] backed by the flutter_webrtc plugin.
class DeviceCallRtcController implements CallRtcController {
  DeviceCallRtcController({required this.isVideo});

  final bool isVideo;

  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  RTCVideoRenderer? _localRenderer;
  RTCVideoRenderer? _remoteRenderer;
  MediaStream? _remoteStream;
  bool _muted = false;
  bool _cameraEnabled = true;

  final StreamController<RTCIceCandidate> _candidateController =
      StreamController<RTCIceCandidate>.broadcast();
  final StreamController<void> _connectedController =
      StreamController<void>.broadcast();

  @override
  bool get muted => _muted;

  @override
  bool get cameraEnabled => _cameraEnabled;

  @override
  Stream<RTCIceCandidate> get localCandidates => _candidateController.stream;

  @override
  Stream<void> get connected => _connectedController.stream;

  @override
  Future<void> initialize() async {
    if (_peer != null) return;
    await _ensurePermissions();
    final RTCPeerConnection peer = await createPeerConnection(<String, dynamic>{
      'iceServers': <Map<String, dynamic>>[
        <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
        <String, dynamic>{'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'iceCandidatePoolSize': 0,
    });
    _peer = peer;

    peer.onIceCandidate = (RTCIceCandidate candidate) {
      _candidateController.add(candidate);
    };
    peer.onTrack = (RTCTrackEvent event) {
      _remoteStream = event.streams.firstOrNull;
      if (_remoteStream != null && _remoteRenderer != null) {
        _remoteRenderer!.srcObject = _remoteStream;
      }
    };
    peer.onConnectionState = (RTCPeerConnectionState state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (!_connectedController.isClosed) {
          _connectedController.add(null);
        }
      }
    };

    final MediaStream localStream;
    try {
      localStream = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
        'audio': true,
        'video': isVideo,
      });
    } on PlatformException catch (e) {
      throw StateError(_permissionMessageFrom(e));
    } catch (_) {
      throw StateError(
        isVideo
            ? 'Camera and microphone access are required for video calls.'
            : 'Microphone access is required to make calls.',
      );
    }
    _localStream = localStream;
    for (final MediaStreamTrack track in localStream.getTracks()) {
      await peer.addTrack(track, localStream);
    }

    if (isVideo) {
      _localRenderer = RTCVideoRenderer();
      await _localRenderer!.initialize();
      _localRenderer!.srcObject = localStream;
      _remoteRenderer = RTCVideoRenderer();
      await _remoteRenderer!.initialize();
      if (_remoteStream != null) {
        _remoteRenderer!.srcObject = _remoteStream;
      }
    }
  }

  @override
  Future<RTCSessionDescription> createOffer() async {
    final RTCPeerConnection peer = _requirePeer();
    final RTCSessionDescription offer = await peer.createOffer();
    await peer.setLocalDescription(offer);
    return offer;
  }

  @override
  Future<RTCSessionDescription> createAnswer(RTCSessionDescription offer) async {
    final RTCPeerConnection peer = _requirePeer();
    await peer.setRemoteDescription(offer);
    final RTCSessionDescription answer = await peer.createAnswer();
    await peer.setLocalDescription(answer);
    return answer;
  }

  @override
  Future<void> setRemoteDescription(RTCSessionDescription answer) async {
    await _requirePeer().setRemoteDescription(answer);
  }

  @override
  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    await _requirePeer().addCandidate(candidate);
  }

  @override
  Future<void> toggleMute() async {
    _muted = !_muted;
    final MediaStream? stream = _localStream;
    if (stream == null) return;
    for (final MediaStreamTrack track in stream.getAudioTracks()) {
      track.enabled = !_muted;
    }
  }

  @override
  Future<void> toggleCamera() async {
    if (!isVideo) return;
    _cameraEnabled = !_cameraEnabled;
    final MediaStream? stream = _localStream;
    if (stream == null) return;
    for (final MediaStreamTrack track in stream.getVideoTracks()) {
      track.enabled = _cameraEnabled;
    }
  }

  @override
  Future<void> switchCamera() async {
    if (!isVideo) return;
    final MediaStream? stream = _localStream;
    if (stream == null) return;
    final MediaStreamTrack? videoTrack = stream.getVideoTracks().firstOrNull;
    if (videoTrack == null) return;
    try {
      await Helper.switchCamera(videoTrack);
    } on Exception {
      // Some devices/platforms can't switch mid-call; the call keeps running.
    }
  }

  @override
  Widget? get localView {
    final RTCVideoRenderer? renderer = _localRenderer;
    if (renderer == null) return null;
    return RTCVideoView(renderer);
  }

  @override
  Widget? get remoteView {
    final RTCVideoRenderer? renderer = _remoteRenderer;
    if (renderer == null) return null;
    return RTCVideoView(renderer);
  }

  RTCPeerConnection _requirePeer() {
    final RTCPeerConnection? peer = _peer;
    if (peer == null) {
      throw StateError('CallRtcController.initialize() must be called first.');
    }
    return peer;
  }

  /// Requests the microphone (and camera for video calls) up front so the
  /// denial path produces a clear, recoverable error instead of an opaque
  /// getUserMedia failure.
  Future<void> _ensurePermissions() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    if (!await Permission.microphone.request().isGranted) {
      throw StateError('Microphone access is required to make calls.');
    }
    if (isVideo && !await Permission.camera.request().isGranted) {
      throw StateError('Camera access is required for video calls.');
    }
  }

  String _permissionMessageFrom(PlatformException e) {
    final String code = e.code.toLowerCase();
    final bool permissionIssue = code.contains('denied') ||
        code.contains('permission') ||
        code.contains('notallow');
    if (!permissionIssue) {
      return 'Call failed. Check your connection and try again.';
    }
    return isVideo
        ? 'Camera and microphone access are required for video calls.'
        : 'Microphone access is required to make calls.';
  }

  @override
  Future<void> dispose() async {
    await _candidateController.close();
    await _connectedController.close();
    await _peer?.close();
    final RTCVideoRenderer? localRenderer = _localRenderer;
    if (localRenderer != null) {
      localRenderer.srcObject = null;
      await localRenderer.dispose();
    }
    final RTCVideoRenderer? remoteRenderer = _remoteRenderer;
    if (remoteRenderer != null) {
      remoteRenderer.srcObject = null;
      await remoteRenderer.dispose();
    }
    await _localStream?.dispose();
    await _remoteStream?.dispose();
    _peer = null;
    _localStream = null;
  }
}
