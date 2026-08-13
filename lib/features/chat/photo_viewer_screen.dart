import 'package:flutter/material.dart';

import 'widgets/media_message_bubble.dart';

/// Full-screen photo viewer: black background, pinch-to-zoom/pan, and a close
/// button. Opens from image message bubbles.
class PhotoViewerScreen extends StatelessWidget {
  const PhotoViewerScreen({super.key, required this.url, this.messageId});

  final String url;
  final String? messageId;

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: InteractiveViewer(
              maxScale: 5,
              minScale: 1,
              child: Center(
                child: MediaImage(
                  url: url,
                  width: size.width,
                  height: size.height,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: SafeArea(
              child: IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
                color: Colors.white,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
