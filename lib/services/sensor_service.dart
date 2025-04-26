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

  // For pothole annotations
  Map<int, Map<String, dynamic>> _annotations = {};

  // For file saving
  String _recordingDirPath = '';

  void startRecording({String recordingDirPath = ''}) {
    if (_isRecording) return;

    _isRecording = true;
    _sensorData = [];
    _startTime = DateTime.now();
    _recordingStartTime = _startTime;
    _lastAccelReading = null;
    _lastGyroReading = null;
    _annotations = {};
    _recordingDirPath = recordingDirPath;

    // Add header with metadata and annotation columns
    _sensorData.add([
      'timestamp_ms',
      'sensor_type',
      'x',
      'y',
      'z',
      'is_pothole',     // yes, no, or unmarked
      'user_feedback',  // user_confirmed, user_rejected, timeout
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
              '',  // is_pothole (will be filled later)
              '',  // user_feedback (will be filled later)
              '',  // empty for other columns
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
              '',  // is_pothole (will be filled later)
              '',  // user_feedback (will be filled later)
              '',  // empty for other columns
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

  // Method to annotate a pothole event
  void annotatePothole(DateTime detectionTime, bool isPothole, String feedback) {
    if (_startTime == null || !_isRecording) return;

    final detectionTimestampMs = detectionTime.difference(_startTime!).inMilliseconds;

    _annotations[detectionTimestampMs] = {
      'isPothole': isPothole,
      'feedback': feedback,
      'timestamp': detectionTimestampMs,
    };

    print('Annotated pothole at ${detectionTimestampMs}ms: isPothole=$isPothole, feedback=$feedback');
  }

  Future<String> stopRecording(String videoPath) async {
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
      '',
      '',
    ]);

    // Add annotations info
    _sensorData.add([
      'annotations_count',
      _annotations.length,
      '',
      '',
      '',
      '',
      '',
      '',
      '',
    ]);

    // Apply annotations to the data
    for (int i = 1; i < _sensorData.length; i++) {
      var row = _sensorData[i];

      // Skip metadata rows
      if (row[1] != 'accelerometer' && row[1] != 'gyroscope') {
        continue;
      }

      int timestamp = row[0] as int;

      // Check each annotation to see if this data point falls within its window
      for (var entry in _annotations.entries) {
        int detectionTime = entry.key;
        var annotation = entry.value;

        // If within 10 seconds before or after a detection
        if (timestamp >= detectionTime - 10000 && timestamp <= detectionTime + 10000) {
          // Mark as pothole or not based on feedback
          if (annotation['feedback'] == 'yes') {
            row[5] = 'yes';
            row[6] = 'user_confirmed';
          } else if (annotation['feedback'] == 'no') {
            row[5] = 'no';
            row[6] = 'user_rejected';
          } else if (annotation['feedback'] == 'timeout') {
            row[5] = 'unmarked';
            row[6] = 'timeout';
          }
          break;
        }
      }
    }

    // Determine where to save the CSV file
    String csvPath;
    if (_recordingDirPath.isNotEmpty) {
      // Use the provided directory path
      csvPath = '$_recordingDirPath/sensor_data.csv';
    } else {
      // Extract directory from the video path
      final directory = File(videoPath).parent;
      csvPath = '${directory.path}/sensor_data.csv';
    }

    // Save data to CSV file
    final file = File(csvPath);

    // Ensure the directory exists
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }

    String csv = const ListToCsvConverter().convert(_sensorData);
    await file.writeAsString(csv);

    return csvPath;
  }

  void dispose() {
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
  }
}
