import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Result returned once the user completes and confirms the liveness flow.
/// `selfie` is the final ("down") capture, kept for backward compatibility
/// with existing upload code. `poseImages` holds all 4 snapshots keyed by
/// 'center' / 'right' / 'left' / 'down' so the backend/admin can verify
/// the person moved correctly, not just that one photo was taken.
class LivenessResult {
  final Uint8List selfie;
  final Map<String, Uint8List> poseImages;
  const LivenessResult({required this.selfie, required this.poseImages});
}

class LivenessCheckPage extends StatefulWidget {
  const LivenessCheckPage({super.key});

  @override
  State<LivenessCheckPage> createState() => _LivenessCheckPageState();
}

enum _Step { center, right, left, down, review }

/// How close the user's face is to the camera, relative to the frame.
enum _Distance { tooFar, tooClose, ok }

class _LivenessCheckPageState extends State<LivenessCheckPage> {
  CameraController? _controller;
  CameraDescription? _frontCamera;

  // Accurate mode + landmarks gives real confirmation that a complete,
  // unobstructed face is present. Fast mode skips landmark detection
  // entirely, which is why it was triggering on partial/blurry/obstructed
  // faces (or even no face at all near the frame edges).
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableClassification: false,
      enableLandmarks: true,
      enableTracking: false,
    ),
  );

  bool _isBusy = false;
  bool _initializing = true;
  bool _capturing = false; // true while snapping a still + restarting stream
  String? _error;

  _Step _step = _Step.center;
  int _holdFrames = 0;
  static const int _framesToConfirm = 6;
  static const double _yawThreshold = 22;
  static const double _pitchDownThreshold = -12;

  // Face bounding-box area as a fraction of the full frame area. Tune these
  // if "move closer"/"move back" triggers too eagerly or not eagerly enough
  // on real devices.
  static const double _minFaceAreaRatio = 0.06; // below this => too far
  static const double _maxFaceAreaRatio = 0.55; // above this => too close

  // How close (in pixels) the face bounding box can get to the edge of the
  // frame before we reject it as "cut off" / not fully in view.
  static const double _edgeMargin = 8.0;

  // Live guidance shown to the user: null when everything is fine (pose
  // instruction is shown instead), otherwise a message telling them what
  // to fix (no face, too close, too far, face not fully visible, etc).
  String? _guidanceMessage;

  // Throttled debug counter — used to print the real face/frame ratio to
  // the console every ~15 frames so we can calibrate the distance
  // thresholds against this specific device instead of guessing blind.
  int _debugFrameCounter = 0;

  static const List<_Step> _order = [
    _Step.center,
    _Step.right,
    _Step.left,
    _Step.down,
  ];

  // Snapshots captured as each pose is confirmed.
  final Map<_Step, Uint8List> _poseImages = {};

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    try {
      final cameras = await availableCameras();
      _frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        _frontCamera!,
        ResolutionPreset.medium,
        enableAudio: false,
        // IMPORTANT: yuv420, NOT nv21. The camera_android_camerax plugin's
        // own native NV21 packer has a buffer-overrun bug on some
        // devices/resolutions (throws "newPosition > limit"). Requesting
        // yuv420 avoids that native path entirely; we do the NV21
        // conversion ourselves in Dart in _yuv420ToNv21() below.
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      setState(() => _initializing = false);
      await controller.startImageStream(_processCameraImage);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not access the camera. Please check camera '
            'permissions and try again.';
        _initializing = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  InputImage? _toInputImage(CameraImage image) {
    if (_frontCamera == null) return null;
    if (image.planes.length < 3) return null;

    final rotation =
        InputImageRotationValue.fromRawValue(_frontCamera!.sensorOrientation) ??
            InputImageRotation.rotation0deg;

    final Uint8List? nv21Bytes = _yuv420ToNv21(image);
    if (nv21Bytes == null) return null;

    return InputImage.fromBytes(
      bytes: nv21Bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.width, // NV21 output here is tightly packed
      ),
    );
  }

  /// Manually converts a YUV420 CameraImage into a tightly-packed NV21
  /// buffer, with explicit stride handling and bounds checks. Doing this
  /// ourselves in Dart avoids the camera_android_camerax plugin's own
  /// native NV21 packer, which throws IllegalArgumentException
  /// ("newPosition > limit") on some devices/resolutions when
  /// ImageFormatGroup.nv21 is requested directly.
  Uint8List? _yuv420ToNv21(CameraImage image) {
    try {
      final int width = image.width;
      final int height = image.height;
      final int ySize = width * height;
      final int uvSize = width * height ~/ 2;
      final Uint8List nv21 = Uint8List(ySize + uvSize);

      // --- Y plane ---
      final Plane yPlane = image.planes[0];
      if (yPlane.bytesPerRow == width) {
        nv21.setRange(0, ySize, yPlane.bytes);
      } else {
        int destOffset = 0;
        for (int row = 0; row < height; row++) {
          final int rowStart = row * yPlane.bytesPerRow;
          final int rowEnd = rowStart + width;
          if (rowEnd > yPlane.bytes.length) break;
          nv21.setRange(destOffset, destOffset + width, yPlane.bytes, rowStart);
          destOffset += width;
        }
      }

      // --- U/V planes -> interleave as V,U (NV21 order) ---
      final Plane uPlane = image.planes[1];
      final Plane vPlane = image.planes[2];
      final int uvRowStride = uPlane.bytesPerRow;
      final int uvPixelStride = uPlane.bytesPerPixel ?? 1;

      int uvIndex = ySize;
      for (int row = 0; row < height ~/ 2; row++) {
        for (int col = 0; col < width ~/ 2; col++) {
          final int uIndex = row * uvRowStride + col * uvPixelStride;
          final int vIndex = row * uvRowStride + col * uvPixelStride;

          if (vIndex < vPlane.bytes.length &&
              uIndex < uPlane.bytes.length &&
              uvIndex + 1 < nv21.length) {
            nv21[uvIndex] = vPlane.bytes[vIndex];
            nv21[uvIndex + 1] = uPlane.bytes[uIndex];
            uvIndex += 2;
          }
        }
      }

      return nv21;
    } catch (e) {
      debugPrint('YUV420->NV21 conversion error: $e');
      return null;
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isBusy || _step == _Step.review || _capturing) return;
    _isBusy = true;
    try {
      final inputImage = _toInputImage(image);
      if (inputImage == null) return;
      final faces = await _faceDetector.processImage(inputImage);
      if (!mounted) return;
      if (faces.isEmpty) {
        if (_holdFrames != 0 || _guidanceMessage != 'Position your face in the frame') {
          setState(() {
            _holdFrames = 0;
            _guidanceMessage = 'Position your face in the frame';
          });
        }
        return;
      }
      _evaluate(faces.first, image.width, image.height);
    } catch (_) {
      // Ignore single-frame processing errors; the next frame retries.
    } finally {
      _isBusy = false;
    }
  }

  /// Rejects the face unless it's a complete, unobstructed face fully
  /// inside the frame. Guards against three failure modes:
  /// 1. Face partially cut off at the edge of the camera frame.
  /// 2. Face landmarks missing/low-confidence (something is covering part
  ///    of the face — hand, mask, phone, hair, etc).
  /// 3. Face too small/blurry for reliable landmark detection at all.
  bool _isFullUnobstructedFace(Face face, int imgWidth, int imgHeight) {
    final box = face.boundingBox;

    // 1. Must be fully inside the frame with a small margin — no edge cutoff.
    if (box.left < _edgeMargin ||
        box.top < _edgeMargin ||
        box.right > imgWidth - _edgeMargin ||
        box.bottom > imgHeight - _edgeMargin) {
      return false;
    }

    // 2. All key landmarks must be present. If something is covering the
    // face (hand, mask, object), ML Kit typically fails to locate one or
    // more of these even though it still reports a bounding box.
    const requiredLandmarks = [
      FaceLandmarkType.leftEye,
      FaceLandmarkType.rightEye,
      FaceLandmarkType.noseBase,
      FaceLandmarkType.leftMouth,
      FaceLandmarkType.rightMouth,
      FaceLandmarkType.bottomMouth,
    ];
    for (final type in requiredLandmarks) {
      if (face.landmarks[type] == null) return false;
    }

    return true;
  }

  _Distance _checkDistance(Face face, int imgWidth, int imgHeight) {
    final imageArea = imgWidth * imgHeight;
    if (imageArea == 0) return _Distance.ok;
    final faceArea = face.boundingBox.width * face.boundingBox.height;
    final ratio = faceArea / imageArea;

    _debugFrameCounter++;
    if (_debugFrameCounter % 15 == 0) {
      debugPrint(
        '[Liveness] ratio=${ratio.toStringAsFixed(3)} '
        'image=${imgWidth}x$imgHeight '
        'faceBox=${face.boundingBox.width.toStringAsFixed(0)}x'
        '${face.boundingBox.height.toStringAsFixed(0)}',
      );
    }

    if (ratio < _minFaceAreaRatio) return _Distance.tooFar;
    if (ratio > _maxFaceAreaRatio) return _Distance.tooClose;
    return _Distance.ok;
  }

  void _evaluate(Face face, int imgWidth, int imgHeight) {
    // Reject anything that isn't a complete, unobstructed, fully-framed
    // face before doing anything else — treat it exactly like "no face".
    if (!_isFullUnobstructedFace(face, imgWidth, imgHeight)) {
      if (_holdFrames != 0 || _guidanceMessage != 'Keep your whole face in the frame') {
        setState(() {
          _holdFrames = 0;
          _guidanceMessage = 'Keep your whole face in the frame';
        });
      }
      return;
    }

    // Check distance next — no point checking head angle if the user is
    // too close or too far away. This is what tells the user to move
    // closer to or further from the camera.
    final distance = _checkDistance(face, imgWidth, imgHeight);
    if (distance != _Distance.ok) {
      final msg = distance == _Distance.tooFar
          ? 'Move a little closer to the camera'
          : 'Move a little further from the camera';
      if (_guidanceMessage != msg || _holdFrames != 0) {
        setState(() {
          _guidanceMessage = msg;
          _holdFrames = 0;
        });
      }
      return;
    }
    if (_guidanceMessage != null) {
      setState(() => _guidanceMessage = null);
    }

    final yaw = face.headEulerAngleY ?? 0;
    final pitch = face.headEulerAngleX ?? 0;

    bool good;
    switch (_step) {
      case _Step.center:
        good = yaw.abs() < 10 && pitch.abs() < 10;
        break;
      // NOTE: headEulerAngleY is computed from the raw (unmirrored) sensor
      // frame, but the front camera preview shown to the user is mirrored
      // like a selfie/mirror. Because of that mirroring, the sign of yaw
      // is flipped relative to the direction the user actually feels they
      // turned: turning to the user's own right produces a *negative* yaw,
      // and turning to the user's own left produces a *positive* yaw. The
      // two cases below are swapped from the "naive" mapping to match what
      // the user sees on screen.
      case _Step.right:
        good = yaw < -_yawThreshold;
        break;
      case _Step.left:
        good = yaw > _yawThreshold;
        break;
      case _Step.down:
        good = pitch < _pitchDownThreshold;
        break;
      case _Step.review:
        good = false;
        break;
    }

    if (good) {
      _holdFrames++;
      if (_holdFrames >= _framesToConfirm) {
        _advance();
      } else {
        setState(() {});
      }
    } else if (_holdFrames != 0) {
      setState(() => _holdFrames = 0);
    }
  }

  /// Snaps a still photo for the pose currently being confirmed, then moves
  /// to the next pose — or to the review screen once all 4 are captured.
  Future<void> _advance() async {
    _holdFrames = 0;
    final finishedStep = _step;
    setState(() => _capturing = true);

    final img = await _capturePoseImageWithRetry();

    if (img == null) {
      // Capture genuinely failed — stay on this step and tell the user,
      // instead of silently skipping the photo and moving on.
      if (mounted) {
        setState(() => _capturing = false);
        _showCaptureError();
      }
      if (_controller != null && !_controller!.value.isStreamingImages) {
        await _controller!.startImageStream(_processCameraImage);
      }
      return;
    }

    _poseImages[finishedStep] = img;

    if (!mounted) return;
    final currentIndex = _order.indexOf(finishedStep);
    if (currentIndex < _order.length - 1) {
      setState(() {
        _step = _order[currentIndex + 1];
        _capturing = false;
      });
      if (_controller != null && !_controller!.value.isStreamingImages) {
        await _controller!.startImageStream(_processCameraImage);
      }
    } else {
      setState(() {
        _step = _Step.review;
        _capturing = false;
      });
    }
  }

  /// Retries a few times with a short delay, since takePicture() right after
  /// stopImageStream() can throw on some devices while the capture session
  /// is still tearing down.
  Future<Uint8List?> _capturePoseImageWithRetry({int attempts = 3}) async {
    for (var i = 0; i < attempts; i++) {
      try {
        if (_controller != null && _controller!.value.isStreamingImages) {
          await _controller!.stopImageStream();
        }
        await Future.delayed(const Duration(milliseconds: 250));
        final shot = await _controller?.takePicture();
        if (shot == null) continue;
        return await shot.readAsBytes();
      } catch (e) {
        debugPrint('Pose capture attempt ${i + 1} failed: $e');
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
    return null;
  }

  void _showCaptureError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not capture the photo. Please hold the pose steady and try again.',
        ),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  /// Called from the review screen. User confirms the 4 photos are good.
  void _confirmAndFinish() {
    final down = _poseImages[_Step.down];
    if (down == null || _poseImages.length < _order.length) {
      // Shouldn't normally happen, but guard just in case.
      return;
    }
    Navigator.pop(
      context,
      LivenessResult(
        selfie: down,
        poseImages: {
          'center': _poseImages[_Step.center]!,
          'right': _poseImages[_Step.right]!,
          'left': _poseImages[_Step.left]!,
          'down': _poseImages[_Step.down]!,
        },
      ),
    );
  }

  /// Called from the review screen. User wants to redo the whole sequence.
  Future<void> _retakeAll() async {
    _poseImages.clear();
    setState(() {
      _step = _Step.center;
      _holdFrames = 0;
      _guidanceMessage = null;
    });
    if (_controller != null && !_controller!.value.isStreamingImages) {
      await _controller!.startImageStream(_processCameraImage);
    }
  }

  String get _instruction {
    switch (_step) {
      case _Step.center:
        return 'Center your face in the frame';
      case _Step.right:
        return 'Slowly turn your head to the right';
      case _Step.left:
        return 'Slowly turn your head to the left';
      case _Step.down:
        return 'Slowly tilt your head down';
      case _Step.review:
        return 'Review your photos';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_step == _Step.review) {
      return _buildReviewScreen();
    }
    // Distance/position guidance takes priority over the pose instruction —
    // no point telling someone to turn their head if they're too close.
    final displayText = _capturing
        ? 'Capturing photo...'
        : (_guidanceMessage ?? _instruction);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_controller != null && _controller!.value.isInitialized)
            CameraPreview(_controller!)
          else if (_initializing)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),

          Center(
            child: Container(
              width: 240,
              height: 300,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(140),
                border: Border.all(
                  // Amber border while we need the user to reposition,
                  // white/normal once distance is fine.
                  color: _guidanceMessage != null
                      ? Colors.amberAccent
                      : Colors.white,
                  width: 3,
                ),
              ),
            ),
          ),

          Positioned(
            top: 64,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _order.map(_dot).toList(),
            ),
          ),

          Positioned(
            top: 96,
            left: 24,
            right: 24,
            child: Text(
              displayText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _guidanceMessage != null
                    ? Colors.amberAccent
                    : Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          // Live progress bar — fills up as the pose is held steady, so
          // it's clear the scanner is actually working frame-to-frame
          // rather than just showing which step is active. Stays empty
          // while the user still needs to reposition.
          Positioned(
            top: 132,
            left: 40,
            right: 40,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: _capturing
                    ? 1.0
                    : (_guidanceMessage != null
                        ? 0.0
                        : (_holdFrames / _framesToConfirm).clamp(0.0, 1.0)),
                backgroundColor: Colors.white24,
                color: const Color(0xFF91E6C1),
                minHeight: 6,
              ),
            ),
          ),

          const Positioned(
            bottom: 48,
            left: 24,
            right: 24,
            child: Text(
              'Hold each pose steady until the dot fills in. We\'ll let you '
              'know if you need to move closer or further from the camera.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),

          Positioned(
            top: 12,
            left: 12,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context, null),
            ),
          ),

          if (_error != null)
            Container(
              color: Colors.black87,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.videocam_off_rounded,
                      color: Colors.white54, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Side-by-side (2x2) review of the 4 captured poses, so the user (and
  /// the system) can visually confirm all angles were captured correctly
  /// before the account is created.
  Widget _buildReviewScreen() {
    final labels = {
      _Step.center: 'Center',
      _Step.right: 'Right',
      _Step.left: 'Left',
      _Step.down: 'Down',
    };

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 8),
              const Text(
                'Confirm Your Photos',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Make sure your face is clearly visible in each pose.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  children: _order.map((step) {
                    final img = _poseImages[step];
                    return Column(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: img != null
                                ? Image.memory(img, fit: BoxFit.cover, width: double.infinity)
                                : Container(
                                    color: Colors.white12,
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.error_outline,
                                        color: Colors.white38),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(labels[step]!,
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _retakeAll,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        side: const BorderSide(color: Colors.white38),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: const Text('Retake All',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _confirmAndFinish,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF91E6C1),
                        foregroundColor: const Color(0xFF1F2937),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: const Text('Confirm',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot(_Step s) {
    final currentIndex = _order.indexOf(_step == _Step.review ? _Step.down : _step);
    final dotIndex = _order.indexOf(s);
    final isDone = dotIndex < currentIndex || _step == _Step.review;
    final isActive = dotIndex == currentIndex && _step != _Step.review;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDone || isActive ? const Color(0xFF91E6C1) : Colors.white24,
      ),
    );
  }
}