import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import '../models/recording_data.dart';
import 'sensor_service.dart';

class CameraService {
  CameraController? controller;
  List<CameraDescription> cameras = [];
  bool isInitialized = false;
  bool isRecording = false;
  Completer<void>? _videoStartCompleter;

  // Make sensor service accessible
  final SensorService _sensorService = SensorService();
  SensorService get sensorService => _sensorService;

  // Callbacks
  Function(DateTime)? onPotholeDetected;
  Function(String, double, Map<String, List<double>>)? onCalibrationComplete;

  CameraService() {
    // Set the callback in sensor service that will notify this class
    _sensorService.onPotholeDetected = _handlePotholeDetection;
    _sensorService.onCalibrationComplete = onCalibrationComplete;
  }

  double get bumpThreshold => _sensorService.bumpThreshold;

  void setBumpThreshold(double value) {
    _sensorService.setBumpThreshold(value);
  }

  // Handle pothole detection from sensor service
  void _handlePotholeDetection(DateTime detectionTime) {
    // Only trigger UI callback if we're recording and a callback is set
    if (isRecording && onPotholeDetected != null) {
      onPotholeDetected!(detectionTime);
    }
  }

  Future<void> initializeCamera() async {
    try {
      cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No cameras available');
      }

      // Use the first back-facing camera
      final backCamera = cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false, // Keep audio disabled
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller!.initialize();

      // Don't lock the orientation - allow the app to adapt

      isInitialized = true;
    } catch (e) {
      print('Error initializing camera: $e');
      rethrow;
    }
  }

  Future<RecordingData> startRecording() async {
    if (!isInitialized || isRecording || controller == null) {
      throw Exception('Camera not ready for recording');
    }

    final timestamp = DateTime.now();
    final formattedDate = DateFormat('yyyyMMdd_HHmmss').format(timestamp);
    final String recordingFolderName = 'Recording_$formattedDate';

    // --- Get Platform-Specific Base Path STRING ---
    String baseRecordingsPath;
    if (Platform.isAndroid) {
      // Hardcode path to Downloads directory on Android

      baseRecordingsPath = '/storage/emulated/0/Download/PotholeDetectorRecordings';
      print('Using Android Downloads base path: $baseRecordingsPath');
    } else {
      // Use application documents directory for iOS and other platforms
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      baseRecordingsPath = path.join(appDocDir.path, 'PotholeDetectorRecordings');
      print('Using iOS/Other documents base path: $baseRecordingsPath');
    }
    // ---

    // Construct the full path for this specific recording's directory
    final String recordingDirPath = path.join(baseRecordingsPath, recordingFolderName);
    final Directory recordingDir = Directory(recordingDirPath);

    // Ensure the base and specific directories exist
    try {
      if (!await recordingDir.exists()) {
        await recordingDir.create(recursive: true);
        print('Created recording directory: ${recordingDir.path}');
      } else {
        print('Recording directory already exists: ${recordingDir.path}');
      }
    } catch (e) {
      print('Error creating directory: ${recordingDir.path} - $e');
      throw Exception('Failed to create recording directory. Check permissions.');
    }


    // Create a completer to track when video recording actually starts
    _videoStartCompleter = Completer<void>();

    // Start video recording and sensor recording simultaneously with precise timing

    // Prepare sensor service, passing the correct directory path
    _sensorService.startRecording(recordingDirPath: recordingDir.path);

    // Start video recording
    try {
      await controller!.startVideoRecording();
    } catch(e) {
      print("Error starting video recording: $e");
      // Clean up sensor service if video fails to start
      await _sensorService.stopRecording(''); // Use await
      isRecording = false; // Ensure state is correct
      throw Exception("Failed to start video recording.");
    }

    // Mark as recording after video starts
    isRecording = true;
    _videoStartCompleter?.complete(); // Ensure this completes

    final videoFilePath = path.join(recordingDir.path, 'video.mp4');
    final sensorFilePath = path.join(recordingDir.path, 'sensor_data.csv');

    print('Recording started. Video path: $videoFilePath, Sensor path: $sensorFilePath');

    return RecordingData(
      id: recordingFolderName, // Use folder name as ID
      videoPath: videoFilePath,
      sensorDataPath: sensorFilePath,
      // Use the original non-nullable timestamp captured at the start
      timestamp: timestamp,
    );
  }
  Future<RecordingData> stopRecording(RecordingData recordingData) async {
    if (!isRecording || controller == null) {
      throw Exception('Not currently recording');
    }

    // Wait for video to finish
    XFile videoFile;
    try {
      videoFile = await controller!.stopVideoRecording();
    } catch (e) {
      print("Error stopping video recording: $e");
      // Even if stopping fails, try to stop sensors and mark as not recording
      isRecording = false;
      _sensorService.stopRecording(recordingData.videoPath); // Attempt to save sensor data
      throw Exception('Failed to stop video recording cleanly.');
    }


    // Mark as not recording BEFORE potentially long file operations
    isRecording = false;

    // Stop sensor recording - ensure this path matches the one used above
    final String sensorDataPath = await _sensorService.stopRecording(recordingData.videoPath); // videoPath here is mainly for fallback dir logic in sensor service if needed

    // Move video file to our final storage location (recordingData.videoPath)
    final File videoSource = File(videoFile.path);
    final File videoDest = File(recordingData.videoPath);

    try {

      final directory = videoDest.parent;
      if (!await directory.exists()) {
        await directory.create(recursive: true);
        print('Re-created directory for video destination: ${directory.path}');
      }


      print('Copying video from ${videoSource.path} to ${videoDest.path}');
      await videoSource.copy(videoDest.path);
      print('Video copied successfully.');


      try {
        if (await videoSource.exists()) {
          await videoSource.delete();
          print('Deleted temporary video file: ${videoSource.path}');
        }
      } catch (e) {
        print('Warning: Could not delete temporary video file: $e');
      }
    } catch (e) {
      print('Error moving/copying video file: $e');
      print('Using temporary video path due to copy error: ${videoFile.path}');
      recordingData = RecordingData(
        id: recordingData.id,
        videoPath: videoFile.path, // Fallback to temp path
        sensorDataPath: sensorDataPath,
        timestamp: recordingData.timestamp,
      );

    }

    print('Recording stopped. Final Video: ${recordingData.videoPath}, Sensor: ${sensorDataPath}');
    return recordingData;
  }

  void dispose() {
    // Stop recording if active when disposing
    if (isRecording && controller != null && controller!.value.isRecordingVideo) {
      print("CameraService dispose called while recording. Attempting to stop.");

      controller!.stopVideoRecording().catchError((Object e, StackTrace? stackTrace) {

        print("Error stopping video during dispose: $e");

        return Future<XFile>.error(e, stackTrace);
      });
      _sensorService.stopRecording(''); // Stop sensor with dummy path
    }
    controller?.dispose();
    _sensorService.dispose();
    isInitialized = false;
    isRecording = false;
    print("CameraService disposed.");
  }
}