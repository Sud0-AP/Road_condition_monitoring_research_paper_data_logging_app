import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:csv/csv.dart';
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

  // For bump detection
  final List<AccelerometerEvent> _recentAccelReadings = [];
  static const int _bufferSize = 50; // Store last 50 readings (approx 0.5 seconds at 100Hz)
  double _baselineAccelMagnitude = 9.8; // Starting with standard gravity
  int _calibrationReadings = 0;
  static const int _calibrationSize = 200; // Calibration period (approx 2 seconds)
  static double _bumpThreshold = 5.0;
  static const int _cooldownMs = 3000; // Minimum time between detections (3 seconds)
  DateTime? _lastDetectionTime;

  // Callback function that will be set by CameraService
  Function(DateTime)? onPotholeDetected;

  double get bumpThreshold => _bumpThreshold;

  void setBumpThreshold(double value) {
    _bumpThreshold = value;
    print('Bump threshold set to: $value');
  }

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

    // Reset bump detection variables
    _recentAccelReadings.clear();
    _calibrationReadings = 0;
    _baselineAccelMagnitude = 9.8; // Reset to standard gravity
    _lastDetectionTime = null;

    // Add header with metadata and annotation columns
    _sensorData.add([
      'timestamp_ms',
      'sensor_type',
      'x',
      'y',
      'z',
      'magnitude', // Add magnitude column
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

            // Calculate magnitude for detection
            final magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);

            // Process for bump detection
            _processBumpDetection(event, magnitude, now);

            final timestamp = now.difference(_startTime!).inMilliseconds;
            _sensorData.add([
              timestamp,
              'accelerometer',
              event.x,
              event.y,
              event.z,
              magnitude,  // Store magnitude in data
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
              '',  // magnitude (only for accelerometer)
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

  // Process accelerometer data for bump detection
  void _processBumpDetection(AccelerometerEvent event, double magnitude, DateTime now) {
    // Add to recent readings buffer
    _recentAccelReadings.add(event);
    if (_recentAccelReadings.length > _bufferSize) {
      _recentAccelReadings.removeAt(0); // Remove oldest reading
    }

    // First calibrate to establish baseline
    if (_calibrationReadings < _calibrationSize) {
      // During calibration, update baseline
      _baselineAccelMagnitude = (_baselineAccelMagnitude * _calibrationReadings + magnitude) / (_calibrationReadings + 1);
      _calibrationReadings++;
      return; // Skip detection during calibration
    }

    // Check for cooldown period
    if (_lastDetectionTime != null) {
      final timeSinceLastDetection = now.difference(_lastDetectionTime!).inMilliseconds;
      if (timeSinceLastDetection < _cooldownMs) {
        return; // Still in cooldown period
      }
    }

    // Calculate variance and standard deviation in recent readings
    double sum = 0;
    double sumSquared = 0;

    for (var accel in _recentAccelReadings) {
      double readingMagnitude = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z);
      sum += readingMagnitude;
      sumSquared += readingMagnitude * readingMagnitude;
    }

    double mean = sum / _recentAccelReadings.length;
    double variance = (sumSquared / _recentAccelReadings.length) - (mean * mean);
    double stdDev = sqrt(variance);

    // Calculate delta from baseline (how much current magnitude differs from baseline)
    double delta = abs(magnitude - _baselineAccelMagnitude);

    // Check if magnitude exceeds threshold and has significant deviation
    if (delta > _bumpThreshold && stdDev > 1.0) {
      // We detected a bump!
      _lastDetectionTime = now;

      // Notify via callback if set
      if (onPotholeDetected != null) {
        onPotholeDetected!(now);
      }

      print('Bump detected! Magnitude: $magnitude, Delta: $delta, StdDev: $stdDev');
    }

    // Gradually update baseline (adaptive baseline)
    // Use a small learning factor to slowly adapt to changing conditions
    _baselineAccelMagnitude = _baselineAccelMagnitude * 0.99 + magnitude * 0.01;
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
            row[6] = 'yes';
            row[7] = 'user_confirmed';
          } else if (annotation['feedback'] == 'no') {
            row[6] = 'no';
            row[7] = 'user_rejected';
          } else if (annotation['feedback'] == 'timeout') {
            row[6] = 'unmarked';
            row[7] = 'timeout';
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

double abs(double value) {
  return value < 0 ? -value : value;
}