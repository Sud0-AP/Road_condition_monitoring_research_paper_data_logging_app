import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/camera_service.dart';
import '../models/recording_data.dart';
import '../widgets/pothole_prompt_overlay.dart';
import '../widgets/threshold_adjustment_popup.dart';
import 'recordings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final CameraService _cameraService = CameraService();
  RecordingData? _currentRecording;
  bool _isInitializing = true;
  String _errorMessage = '';

  // For pothole prompt
  bool _showingPotholePrompt = false;
  DateTime? _currentSpikeTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestPermissionsAndInitialize();

    // Set the pothole detection callback
    _cameraService.onPotholeDetected = _handleRealPotholeDetection;
  }

// Add this method to handle real pothole detection events
  void _handleRealPotholeDetection(DateTime detectionTime) {
    // Only show prompt if not already showing one and we're recording
    if (!_showingPotholePrompt && _cameraService.isRecording) {
      setState(() {
        _showingPotholePrompt = true;
        _currentSpikeTime = detectionTime;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraService.controller == null) return;

    if (state == AppLifecycleState.inactive) {
      _cameraService.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _requestPermissionsAndInitialize() async {
    setState(() {
      _isInitializing = true;
      _errorMessage = '';
    });

    try {
      // Request only necessary permissions (removed location permission)
      Map<Permission, PermissionStatus> statuses = await [
        Permission.camera,
        Permission.storage,
        // Add these for Android 13+
        Permission.photos,
        Permission.videos,
        Permission.microphone,
        // For Android 11+ to access external storage
        Permission.manageExternalStorage,
      ].request();

      // Check if all critical permissions are granted
      bool allGranted = true;
      String missingPermissions = '';

      if (statuses[Permission.camera] != PermissionStatus.granted) {
        allGranted = false;
        missingPermissions += 'Camera, ';
      }

      // Check for storage permissions based on Android version
      if (statuses[Permission.storage] != PermissionStatus.granted &&
          statuses[Permission.photos] != PermissionStatus.granted &&
          statuses[Permission.videos] != PermissionStatus.granted) {
        allGranted = false;
        missingPermissions += 'Storage, ';
      }

      // Create the Downloads/PotholeDetector folder if it doesn't exist
      final downloadsDir = Directory('/storage/emulated/0/Download/PotholeDetector');
      if (!await downloadsDir.exists()) {
        try {
          await downloadsDir.create(recursive: true);
        } catch (e) {
          print('Error creating downloads directory: $e');
        }
      }

      if (allGranted) {
        await _initializeCamera();
      } else {
        setState(() {
          _isInitializing = false;
          _errorMessage = 'Required permissions not granted: ${missingPermissions.substring(0, missingPermissions.length - 2)}';
        });
      }
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _errorMessage = 'Error requesting permissions: $e';
      });
    }
  }
  Future<void> _initializeCamera() async {
    setState(() {
      _isInitializing = true;
      _errorMessage = '';
    });

    try {
      await _cameraService.initializeCamera();
      setState(() {
        _isInitializing = false;
      });
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _errorMessage = 'Failed to initialize camera: $e';
      });
    }
  }

  Future<void> _toggleRecording() async {
    if (_cameraService.isRecording) {
      // Stop recording
      if (_currentRecording != null) {
        try {
          await _cameraService.stopRecording(_currentRecording!);
          setState(() {
            _currentRecording = null;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recording saved')),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error stopping recording: $e')),
          );
        }
      }
    } else {
      // Start recording
      try {
        final recordingData = await _cameraService.startRecording();
        setState(() {
          _currentRecording = recordingData;
        });
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting recording: $e')),
        );
      }
    }
  }

  // New method to show the threshold adjustment popup
  void _showThresholdAdjustment() {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    showDialog(
      context: context,
      builder: (context) => ThresholdAdjustmentPopup(
        currentThreshold: _cameraService.bumpThreshold,
        onThresholdChanged: (value) {
          _cameraService.setBumpThreshold(value);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Bump sensitivity threshold set to ${value.toStringAsFixed(1)}')),
          );
        },
        isLandscape: isLandscape,
      ),
    );
  }

  // Handle pothole prompt response
  void _handlePotholeResponse(bool isPothole) {
    if (_currentSpikeTime != null && _currentRecording != null) {
      // Access the sensor service through camera service
      _cameraService.sensorService.annotatePothole(
          _currentSpikeTime!,
          isPothole,
          isPothole ? 'yes' : 'no'
      );

      // Show feedback to user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isPothole
              ? 'Marked as pothole'
              : 'Marked as not a pothole'),
          duration: const Duration(seconds: 1),
        ),
      );
    }

    setState(() {
      _showingPotholePrompt = false;
      _currentSpikeTime = null;
    });
  }

  // Handle pothole prompt timeout
  void _handlePromptTimeout() {
    if (_currentSpikeTime != null && _currentRecording != null) {
      _cameraService.sensorService.annotatePothole(
          _currentSpikeTime!,
          false,
          'timeout'
      );
    }

    setState(() {
      _showingPotholePrompt = false;
      _currentSpikeTime = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Get the current orientation
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    if (_isInitializing) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage,
                style: TextStyle(color: Colors.white, fontSize: 16.sp),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 20.h),
              ElevatedButton(
                onPressed: _requestPermissionsAndInitialize,
                child: const Text('Grant Permissions'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_cameraService.isInitialized || _cameraService.controller == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: ElevatedButton(
            onPressed: _initializeCamera,
            child: const Text('Initialize Camera'),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview - Using a consistent approach that works in both orientations
          SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: CameraPreview(_cameraService.controller!),
          ),

          // Controls - positioned based on orientation
          if (isLandscape)
          // Landscape layout - controls on the right side, smaller buttons
            Positioned(
              right: 16.w,
              top: 0,
              bottom: 0,
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Record Button - smaller in landscape
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FloatingActionButton(  // Regular size instead of large
                          heroTag: 'record',
                          backgroundColor: _cameraService.isRecording
                              ? Colors.red.withOpacity(0.8)
                              : Colors.white.withOpacity(0.8),
                          onPressed: _toggleRecording,
                          child: Icon(
                            _cameraService.isRecording ? Icons.stop : Icons.fiber_manual_record,
                            color: _cameraService.isRecording ? Colors.white : Colors.red,
                            size: 24.sp,  // Smaller icon
                          ),
                        ),
                        SizedBox(height: 4.h),  // Less spacing
                        Text(
                          _cameraService.isRecording ? 'Stop' : 'Start',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.sp,  // Smaller text
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                offset: const Offset(1.0, 1.0),
                                blurRadius: 3.0,
                                color: Colors.black.withOpacity(0.7),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: 16.h),  // Less spacing

                    // Sensitivity Settings Button - smaller in landscape
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FloatingActionButton.small(  // Small size
                          heroTag: 'sensitivity',
                          backgroundColor: Colors.amber.withOpacity(0.8),
                          onPressed: _showThresholdAdjustment,
                          child: const Icon(Icons.tune, color: Colors.white, size: 20),  // Changed icon
                        ),
                        SizedBox(height: 4.h),  // Less spacing
                        Text(
                          'Settings',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10.sp,  // Smaller text
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                offset: const Offset(1.0, 1.0),
                                blurRadius: 3.0,
                                color: Colors.black.withOpacity(0.7),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: 16.h),  // Less spacing

                    // Recordings Button - smaller in landscape
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FloatingActionButton.small(  // Small size
                          heroTag: 'recordings',
                          backgroundColor: Colors.black54,
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const RecordingsScreen(),
                              ),
                            );
                          },
                          child: const Icon(Icons.folder, color: Colors.white, size: 20),  // Smaller icon
                        ),
                        SizedBox(height: 4.h),  // Less spacing
                        Text(
                          'Files',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10.sp,  // Smaller text
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                offset: const Offset(1.0, 1.0),
                                blurRadius: 3.0,
                                color: Colors.black.withOpacity(0.7),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          else
          // Portrait layout - controls at the bottom
            Positioned(
              bottom: 30.h,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Recordings Button
                  FloatingActionButton(
                    heroTag: 'recordings',
                    backgroundColor: Colors.black54,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const RecordingsScreen(),
                        ),
                      );
                    },
                    child: const Icon(Icons.folder, color: Colors.white),
                  ),

                  // Record Button
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton.large(
                        heroTag: 'record',
                        backgroundColor: _cameraService.isRecording
                            ? Colors.red.withOpacity(0.8)
                            : Colors.white.withOpacity(0.8),
                        onPressed: _toggleRecording,
                        child: Icon(
                          _cameraService.isRecording ? Icons.stop : Icons.fiber_manual_record,
                          color: _cameraService.isRecording ? Colors.white : Colors.red,
                          size: 36.sp,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        _cameraService.isRecording ? 'Stop' : 'Start Recording',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              offset: const Offset(1.0, 1.0),
                              blurRadius: 3.0,
                              color: Colors.black.withOpacity(0.7),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Sensitivity Settings Button
                  FloatingActionButton(
                    heroTag: 'sensitivity',
                    backgroundColor: Colors.amber.withOpacity(0.8),
                    onPressed: _showThresholdAdjustment,
                    tooltip: 'Adjust Sensitivity Settings',
                    child: const Icon(Icons.tune, color: Colors.white),  // Changed icon to tune
                  ),
                ],
              ),
            ),

          // Recording indicator - positioned based on orientation
          if (_cameraService.isRecording)
            Positioned(
              top: isLandscape ? 20.h : 50.h,
              left: isLandscape ? 20.w : 0,
              right: isLandscape ? null : 0,
              child: SafeArea(
                child: Center(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20.r),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12.w,
                          height: 12.h,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          'RECORDING',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Pothole Prompt Overlay - orientation aware
          if (_showingPotholePrompt)
            PotholePromptOverlay(
              onResponse: _handlePotholeResponse,
              onTimeout: _handlePromptTimeout,
              isLandscape: isLandscape,
            ),
        ],
      ),
    );
  }
}