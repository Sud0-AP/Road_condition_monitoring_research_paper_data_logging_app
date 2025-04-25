import 'dart:async';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:intl/intl.dart';

class SensorService {
  List<List<dynamic>> _sensorData = [];
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  bool _isRecording = false;
  DateTime? _startTime;
  DateTime? _recordingStartTime;

  // Set to approximately 100Hz (10ms intervals)
  static const int _samplingIntervalMs = 10;
  DateTime? _lastAccelReading;
  DateTime? _lastGyroReading;

  void startRecording() {
    if (_isRecording) return;

    _isRecording = true;
    _sensorData = [];
    _startTime = DateTime.now();
    _recordingStartTime = _startTime;
    _lastAccelReading = null;
    _lastGyroReading = null;

    // Add header with metadata
    _sensorData.add([
      'timestamp_ms',
      'sensor_type',
      'x',
      'y',
      'z',
      'recording_start_time',
      DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(_recordingStartTime!),
    ]);

    try {
      // Start accelerometer recording with rate limiting
      _accelerometerSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
        if (_isRecording) {
          final now = DateTime.now();

          // Check if we should record this sample (100Hz = sample every 10ms)
          if (_lastAccelReading == null ||
              now.difference(_lastAccelReading!).inMilliseconds >= _samplingIntervalMs) {

            final timestamp = now.difference(_startTime!).inMilliseconds;
            _sensorData.add([
              timestamp,
              'accelerometer',
              event.x,
              event.y,
              event.z,
              '',
              '',
            ]);

            _lastAccelReading = now;
          }
        }
      }, onError: (error) {
        print("Accelerometer error: $error");
      });
    } catch (e) {
      print("Failed to initialize accelerometer: $e");
    }

    try {
      // Start gyroscope recording with rate limiting
      _gyroscopeSubscription = gyroscopeEvents.listen((GyroscopeEvent event) {
        if (_isRecording) {
          final now = DateTime.now();

          // Check if we should record this sample (100Hz = sample every 10ms)
          if (_lastGyroReading == null ||
              now.difference(_lastGyroReading!).inMilliseconds >= _samplingIntervalMs) {

            final timestamp = now.difference(_startTime!).inMilliseconds;
            _sensorData.add([
              timestamp,
              'gyroscope',
              event.x,
              event.y,
              event.z,
              '',
              '',
            ]);

            _lastGyroReading = now;
          }
        }
      }, onError: (error) {
        print("Gyroscope error: $error");
      });
    } catch (e) {
      print("Failed to initialize gyroscope: $e");
    }
  }

  Future<String> stopRecording(String recordingId) async {
    if (!_isRecording) return '';

    _isRecording = false;

    // Stop sensor subscriptions
    await _accelerometerSubscription?.cancel();
    await _gyroscopeSubscription?.cancel();

    // Add end timestamp
    final endTime = DateTime.now();
    _sensorData.add([
      'end_timestamp',
      '',
      '',
      '',
      '',
      'recording_end_time',
      DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(endTime),
    ]);

    // Calculate duration
    final durationMs = endTime.difference(_recordingStartTime!).inMilliseconds;
    _sensorData.add([
      'duration_ms',
      durationMs,
      '',
      '',
      '',
      '',
      '',
    ]);

    // Add sampling rate info
    _sensorData.add([
      'sampling_rate_hz',
      100,  // Target sampling rate
      '',
      '',
      '',
      '',
      '',
    ]);

    // Save data to temporary file first
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/temp_sensor_data.csv');

    String csv = const ListToCsvConverter().convert(_sensorData);
    await tempFile.writeAsString(csv);

    return tempFile.path;
  }

  void dispose() {
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
  }
}
