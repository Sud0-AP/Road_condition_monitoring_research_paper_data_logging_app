import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../models/recording_data.dart';
import 'sensor_service.dart';

class CameraService {
  CameraController? controller;
  List<CameraDescription> cameras = [];
  bool isInitialized = false;
  bool isRecording = false;
  final SensorService _sensorService = SensorService();

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
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller!.initialize();
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

    final String recordingId = const Uuid().v4();
    isRecording = true;

    // Create directory for this recording in Downloads folder
    final downloadsDir = Directory('/storage/emulated/0/Download/PotholeDetector');
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }

    // Create a unique subfolder with timestamp
    final timestamp = DateTime.now();
    final formattedDate = DateFormat('yyyyMMdd_HHmmss').format(timestamp);
    final recordingDir = Directory('${downloadsDir.path}/Recording_$formattedDate');

    if (!await recordingDir.exists()) {
      await recordingDir.create(recursive: true);
    }

    // Start sensor recording
    _sensorService.startRecording();

    // Start video recording
    await controller!.startVideoRecording();

    return RecordingData(
      id: recordingId,
      videoPath: '${recordingDir.path}/video.mp4',
      sensorDataPath: '${recordingDir.path}/sensor_data.csv',
      timestamp: timestamp,
    );
  }

  Future<RecordingData> stopRecording(RecordingData recordingData) async {
    if (!isRecording || controller == null) {
      throw Exception('Not currently recording');
    }

    // Stop video recording
    final XFile videoFile = await controller!.stopVideoRecording();

    // Stop sensor recording
    final String sensorDataPath = await _sensorService.stopRecording(recordingData.id);

    // Move video file to our storage location
    final File videoSource = File(videoFile.path);
    final File videoDest = File(recordingData.videoPath);

    try {
      // Ensure the directory exists
      final directory = videoDest.parent;
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      // Copy the video file
      await videoSource.copy(videoDest.path);

      // Optional: delete the original file after copying
      try {
        await videoSource.delete();
      } catch (e) {
        print('Warning: Could not delete original video file: $e');
      }

      // Copy sensor data to the same folder
      final tempSensorFile = File(sensorDataPath);
      if (await tempSensorFile.exists()) {
        await tempSensorFile.copy(recordingData.sensorDataPath);
        try {
          await tempSensorFile.delete();
        } catch (e) {
          print('Warning: Could not delete temporary sensor file: $e');
        }
      }
    } catch (e) {
      print('Error copying files: $e');
      // If copy fails, use the original file path
      recordingData = RecordingData(
        id: recordingData.id,
        videoPath: videoFile.path,
        sensorDataPath: sensorDataPath,
        timestamp: recordingData.timestamp,
      );
    }

    isRecording = false;

    return recordingData;
  }

  void dispose() {
    controller?.dispose();
    _sensorService.dispose();
  }
}
