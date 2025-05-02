import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:csv/csv.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:intl/intl.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:collection/collection.dart';

class SensorService {
  List<List<dynamic>> _sensorData = [];
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  bool _isRecording = false;
  DateTime? _startTime;
  DateTime? _recordingStartTime;

  // Timestamp tracking for precise sampling rate calculation
  List<int> _accelerometerTimestamps = [];
  List<int> _gyroscopeTimestamps = [];

  // Timer to enforce 100Hz sampling
  Timer? _samplingTimer;
  static const int _targetSamplingIntervalMs = 10; // 100Hz = 10ms interval

  // For pothole annotations
  Map<int, Map<String, dynamic>> _annotations = {};

  // For file saving
  String _recordingDirPath = '';

  // For bump detection
  final List<AccelerometerEvent> _recentAccelReadings = [];
  static const int _bufferSize =
      50; // Store last 50 readings (approx 0.5 seconds at 100Hz)
  double _baselineAccelMagnitude = 9.8; // Starting with standard gravity
  int _calibrationReadings = 0;
  static const int _calibrationSize =
      200; // Calibration period (approx 2 seconds)
  static double _bumpThreshold = 5.0;
  static const int _cooldownMs =
      3000; // Minimum time between detections (3 seconds)
  DateTime? _lastDetectionTime;

  // Last sensor readings to ensure fixed rate
  AccelerometerEvent? _lastAccelEvent;
  GyroscopeEvent? _lastGyroEvent;

  // For sensor calibration and orientation
  List<AccelerometerEvent> _calibrationAccelData = [];
  List<GyroscopeEvent> _calibrationGyroData = [];
  String _deviceOrientation = 'unknown';
  double _orientationConfidence = 0.0;
  Map<String, List<double>> _sensorOffsets = {
    'accel': [0.0, 0.0, 0.0],
    'gyro': [0.0, 0.0, 0.0]
  };

  // For low-pass filtering
  static const double _alpha =
      0.8; // Filter coefficient (0 = no filtering, 1 = max filtering)
  List<double> _filteredAccel = [0.0, 0.0, 0.0];
  bool _isFirstReading = true;

  // Callback functions
  Function(DateTime)? onPotholeDetected;
  Function(String, double, Map<String, List<double>>)? onCalibrationComplete;

  // Getters
  double get bumpThreshold => _bumpThreshold;
  String get deviceOrientation => _deviceOrientation;
  double get orientationConfidence => _orientationConfidence;
  Map<String, List<double>> get sensorOffsets => _sensorOffsets;

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
    _annotations = {};
    _recordingDirPath = recordingDirPath;

    // Reset sampling rate tracking
    _accelerometerTimestamps = [];
    _gyroscopeTimestamps = [];

    // Reset bump detection variables
    _recentAccelReadings.clear();
    _calibrationReadings = 0;
    _baselineAccelMagnitude = 9.8; // Reset to standard gravity
    _lastDetectionTime = null;

    // Reset calibration data
    _calibrationAccelData.clear();
    _calibrationGyroData.clear();
    _deviceOrientation = 'unknown';
    _orientationConfidence = 0.0;
    _sensorOffsets = {
      'accel': [0.0, 0.0, 0.0],
      'gyro': [0.0, 0.0, 0.0]
    };

    // Wait 1 second for sensors to start collecting data
    print(
        'Please keep the device still in the mount for initial orientation detection...');
    Future.delayed(const Duration(seconds: 1), () {
      // Initial notification with default values
      onCalibrationComplete?.call(
          _deviceOrientation, _orientationConfidence, _sensorOffsets);
    });

    // Add header with metadata and annotation columns
    _sensorData.add([
      'timestamp_ms',
      'accel_x',
      'accel_y',
      'accel_z',
      'accel_magnitude',
      'gyro_x',
      'gyro_y',
      'gyro_z',
      'is_pothole',
      'user_feedback',
      'recording_start_time',
      DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(_recordingStartTime!),
    ]);

    try {
      // Start accelerometer recording - just update the last known event
      _accelerometerSubscription =
          accelerometerEvents.listen((AccelerometerEvent event) {
        _lastAccelEvent = event; // Save the most recent event
        if (_calibrationAccelData.length < 100) {
          // Collect first 100 samples for calibration
          _calibrationAccelData.add(event);
          // Call _startCalibration for each new sample during calibration
          if (_calibrationAccelData.length >= 10) {
            // Start processing after 10 samples
            _processCalibrationData();
          }
        }
      });

      // Start gyroscope recording - just update the last known event
      _gyroscopeSubscription = gyroscopeEvents.listen((GyroscopeEvent event) {
        _lastGyroEvent = event; // Save the most recent event
        if (_calibrationGyroData.length < 100) {
          // Collect first 100 samples for calibration
          _calibrationGyroData.add(event);
          // Process gyro data whenever we have new samples
          if (_calibrationGyroData.length >= 10) {
            // Start processing after 10 samples
            _processGyroData();
          }
        }
      });

      // Set up ONE timer to sample at exactly 100Hz
      _samplingTimer = Timer.periodic(
          const Duration(milliseconds: _targetSamplingIntervalMs), (timer) {
        if (_isRecording && _startTime != null) {
          // Check _startTime for safety
          final now = DateTime.now();
          final timestampMs = now.difference(_startTime!).inMilliseconds;

          // Use the *last available* readings. Handle cases where sensors might not have started yet.
          final currentAccel = _lastAccelEvent;
          final currentGyro = _lastGyroEvent;

          if (currentAccel != null) {
            _accelerometerTimestamps
                .add(timestampMs); // Track timestamps for rate calculation

            // Apply orientation correction
            double correctedX = currentAccel.x;
            double correctedY = currentAccel.y;
            double correctedZ = currentAccel.z;

            // Apply orientation correction based on device orientation
            switch (_deviceOrientation) {
              case 'landscape_left':
                correctedX = currentAccel.y;
                correctedY = -currentAccel.x;
                break;
              case 'landscape_right':
                correctedX = -currentAccel.y;
                correctedY = currentAccel.x;
                break;
              default:
                break;
            }

            // Calculate magnitude using corrected values
            final magnitude = sqrt(correctedX * correctedX +
                correctedY * correctedY +
                correctedZ * correctedZ);

            // Create corrected event for bump detection
            final correctedEvent =
                AccelerometerEvent(correctedX, correctedY, correctedZ);

            // Process for bump detection using corrected values
            _processBumpDetection(correctedEvent, magnitude, now);

            // Get gyro data (use 0s if not available yet)
            final gyroX = currentGyro?.x ?? 0.0;
            final gyroY = currentGyro?.y ?? 0.0;
            final gyroZ = currentGyro?.z ?? 0.0;

            if (currentGyro != null) {
              _gyroscopeTimestamps
                  .add(timestampMs); // Also track gyro timestamps if available
            }

            // Write data row directly
            _sensorData.add([
              timestampMs,
              correctedX,
              correctedY,
              correctedZ,
              magnitude,
              gyroX,
              gyroY,
              gyroZ,
              '', // is_pothole
              '', // user_feedback
              '', // empty for recording_start_time column
            ]);
          } else {
            // Optional: Log if accelerometer data is missing after some time?
            // print("Warning: Missing accelerometer data at timestamp $timestampMs");
          }
        }
      });
    } catch (e) {
      print("Failed to initialize sensors or timer: $e");
      // Attempt cleanup if error occurs during setup
      _isRecording = false;
      _accelerometerSubscription?.cancel();
      _gyroscopeSubscription?.cancel();
      _samplingTimer?.cancel();
    }
  }

  // Process accelerometer data for bump detection
  void _processBumpDetection(
      AccelerometerEvent event, double magnitude, DateTime now) {
    // Add to recent readings buffer
    _recentAccelReadings.add(event);
    if (_recentAccelReadings.length > _bufferSize) {
      _recentAccelReadings.removeAt(0); // Remove oldest reading
    }

    // First calibrate to establish baseline
    if (_calibrationReadings < _calibrationSize) {
      // During calibration, update baseline
      _baselineAccelMagnitude =
          (_baselineAccelMagnitude * _calibrationReadings + magnitude) /
              (_calibrationReadings + 1);
      _calibrationReadings++;
      return; // Skip detection during calibration
    }

    // Check for cooldown period
    if (_lastDetectionTime != null) {
      final timeSinceLastDetection =
          now.difference(_lastDetectionTime!).inMilliseconds;
      if (timeSinceLastDetection < _cooldownMs) {
        return; // Still in cooldown period
      }
    }

    // Calculate variance and standard deviation in recent readings
    double sum = 0;
    double sumSquared = 0;

    for (var accel in _recentAccelReadings) {
      double readingMagnitude =
          sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z);
      sum += readingMagnitude;
      sumSquared += readingMagnitude * readingMagnitude;
    }

    double mean = sum / _recentAccelReadings.length;
    double variance =
        (sumSquared / _recentAccelReadings.length) - (mean * mean);
    double stdDev = sqrt(variance);

    // Calculate delta from baseline (how much current magnitude differs from baseline)
    double delta = (magnitude - _baselineAccelMagnitude).abs();

    // Check if magnitude exceeds threshold and has significant deviation
    if (delta > _bumpThreshold && stdDev > 1.0) {
      // We detected a bump!
      _lastDetectionTime = now;

      // Notify via callback if set
      if (onPotholeDetected != null) {
        onPotholeDetected!(now);
      }

      print(
          'Bump detected! Magnitude: $magnitude, Delta: $delta, StdDev: $stdDev');
    }

    // Gradually update baseline (adaptive baseline)
    // Use a small learning factor to slowly adapt to changing conditions
    _baselineAccelMagnitude = _baselineAccelMagnitude * 0.99 + magnitude * 0.01;
  }

  // Method to annotate a pothole event
  void annotatePothole(
      DateTime detectionTime, bool isPothole, String feedback) {
    if (_startTime == null || !_isRecording) return;

    final detectionTimestampMs =
        detectionTime.difference(_startTime!).inMilliseconds;

    _annotations[detectionTimestampMs] = {
      'isPothole': isPothole,
      'feedback': feedback,
      'timestamp': detectionTimestampMs,
    };

    print(
        'Annotated pothole at ${detectionTimestampMs}ms: isPothole=$isPothole, feedback=$feedback');
  }

  // Calculate actual sampling rate from timestamp data
  double _calculateActualSamplingRate(List<int> timestamps) {
    if (timestamps.length < 2) return 0;

    // Calculate time differences between consecutive samples
    List<int> intervals = [];
    for (int i = 1; i < timestamps.length; i++) {
      intervals.add(timestamps[i] - timestamps[i - 1]);
    }

    // Calculate average interval
    double avgInterval = intervals.reduce((a, b) => a + b) / intervals.length;

    // Convert to Hz (1000 / interval in ms)
    return 1000 / avgInterval;
  }

  // Get device info
  Future<Map<String, dynamic>> _getDeviceInfo() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    Map<String, dynamic> deviceData = <String, dynamic>{};

    try {
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        deviceData = {
          'platform': 'Android',
          'device': androidInfo.device,
          'model': androidInfo.model,
          'manufacturer': androidInfo.manufacturer,
          'androidVersion': androidInfo.version.release,
          'sdkInt': androidInfo.version.sdkInt,
          'product': androidInfo.product,
          'brand': androidInfo.brand,
          'board': androidInfo.board,
          'hardware': androidInfo.hardware,
        };
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        deviceData = {
          'platform': 'iOS',
          'name': iosInfo.name,
          'systemName': iosInfo.systemName,
          'systemVersion': iosInfo.systemVersion,
          'model': iosInfo.model,
          'localizedModel': iosInfo.localizedModel,
          'identifierForVendor': iosInfo.identifierForVendor,
          'isPhysicalDevice': iosInfo.isPhysicalDevice,
          'utsname.sysname': iosInfo.utsname.sysname,
          'utsname.nodename': iosInfo.utsname.nodename,
          'utsname.release': iosInfo.utsname.release,
          'utsname.version': iosInfo.utsname.version,
          'utsname.machine': iosInfo.utsname.machine,
        };
      }
    } catch (e) {
      print('Error getting device info: $e');
    }

    return deviceData;
  }

  Future<String> stopRecording(String videoPath) async {
    if (!_isRecording) return '';

    _isRecording = false;

    // Stop all subscriptions and timers
    await _accelerometerSubscription?.cancel();
    await _gyroscopeSubscription?.cancel();
    _samplingTimer?.cancel();

    // Calculate actual sampling rates (based on timestamps recorded in the single timer)
    double accelSamplingRate =
        _calculateActualSamplingRate(_accelerometerTimestamps);
    double gyroSamplingRate = _calculateActualSamplingRate(
        _gyroscopeTimestamps); // Gyro rate might be lower if it started later

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

    // Add actual sampling rate info
    _sensorData.add([
      'accelerometer_sampling_rate_hz',
      accelSamplingRate.toStringAsFixed(2),
      '',
      '',
      '',
      '',
      '',
      '',
      '',
    ]);

    _sensorData.add([
      'gyroscope_sampling_rate_hz',
      gyroSamplingRate.toStringAsFixed(2),
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

    // Add device info
    Map<String, dynamic> deviceData = await _getDeviceInfo();
    _sensorData.add(['device_info', '', '', '', '', '', '', '', '']);

    // Add orientation and sensor offset information with confidence
    _sensorData.add([
      'orientation',
      _deviceOrientation,
      'confidence',
      '${_orientationConfidence.toStringAsFixed(1)}%',
      '',
      '',
      '',
      '',
      '',
    ]);

    _sensorData.add([
      'sensor_offsets',
      'accel:${_sensorOffsets['accel']![0].toStringAsFixed(3)},${_sensorOffsets['accel']![1].toStringAsFixed(3)},${_sensorOffsets['accel']![2].toStringAsFixed(3)};'
          'gyro:${_sensorOffsets['gyro']![0].toStringAsFixed(3)},${_sensorOffsets['gyro']![1].toStringAsFixed(3)},${_sensorOffsets['gyro']![2].toStringAsFixed(3)}',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
    ]);

    deviceData.forEach((key, value) {
      _sensorData.add([
        key,
        value.toString(),
        '',
        '',
        '',
        '',
        '',
        '',
        '',
      ]);
    });

    // Apply annotations to the data
    // Find the timestamp column index dynamically, assuming it's the first one
    int timestampColIndex =
        0; // Assuming 'timestamp_ms' is the first column (index 0)
    int isPotholeColIndex = -1;
    int feedbackColIndex = -1;

    // Find the correct column indices from the header row
    if (_sensorData.isNotEmpty) {
      var header = _sensorData[0];
      isPotholeColIndex = header.indexWhere((col) => col == 'is_pothole');
      feedbackColIndex = header.indexWhere((col) => col == 'user_feedback');
      // timestampColIndex = header.indexWhere((col) => col == 'timestamp_ms'); // Already assumed 0
    }

    if (isPotholeColIndex != -1 && feedbackColIndex != -1) {
      for (int i = 1; i < _sensorData.length; i++) {
        // Start from 1 to skip header
        var row = _sensorData[i];

        // Skip metadata rows or rows with incorrect structure
        if (row.length <= timestampColIndex || row[timestampColIndex] is! int) {
          continue;
        }

        int timestamp = row[timestampColIndex] as int;

        // Use firstWhereOrNull from collection package for cleaner annotation lookup
        final annotationEntry = _annotations.entries.firstWhereOrNull((entry) {
          int detectionTime = entry.key;
          // Check if timestamp is within the +/- 10-second window
          return timestamp >= detectionTime - 10000 &&
              timestamp <= detectionTime + 10000;
        });

        if (annotationEntry != null) {
          var annotation = annotationEntry.value;
          // Ensure row has enough columns before trying to write
          if (row.length > max(isPotholeColIndex, feedbackColIndex)) {
            if (annotation['feedback'] == 'yes') {
              row[isPotholeColIndex] = 'yes';
              row[feedbackColIndex] = 'user_confirmed';
            } else if (annotation['feedback'] == 'no') {
              row[isPotholeColIndex] = 'no';
              row[feedbackColIndex] = 'user_rejected';
            } else if (annotation['feedback'] == 'timeout') {
              row[isPotholeColIndex] = 'unmarked'; // Changed from ''
              row[feedbackColIndex] = 'timeout';
            }
          } else {
            print("Warning: Row $i has insufficient columns for annotation.");
          }
        }
        // If no annotation matches, the default '' values remain
      }
    } else {
      print(
          "Warning: Could not find 'is_pothole' or 'user_feedback' columns in header.");
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

  void _processCalibrationData() {
    if (_calibrationAccelData.isEmpty) return;

    // Calculate accelerometer offsets and apply low-pass filter
    double sumX = 0, sumY = 0, sumZ = 0;
    double maxVarianceX = 0, maxVarianceY = 0, maxVarianceZ = 0;
    List<double> meanValues = [0.0, 0.0, 0.0];

    // First pass: calculate mean
    for (var event in _calibrationAccelData) {
      sumX += event.x;
      sumY += event.y;
      sumZ += event.z;
    }

    int samples = _calibrationAccelData.length;
    meanValues[0] = sumX / samples;
    meanValues[1] = sumY / samples;
    meanValues[2] = sumZ / samples;

    // Second pass: calculate variance to detect movement
    for (var event in _calibrationAccelData) {
      double varX = pow(event.x - meanValues[0], 2).toDouble();
      double varY = pow(event.y - meanValues[1], 2).toDouble();
      double varZ = pow(event.z - meanValues[2], 2).toDouble();

      maxVarianceX = max(maxVarianceX, varX);
      maxVarianceY = max(maxVarianceY, varY);
      maxVarianceZ = max(maxVarianceZ, varZ);
    }

    // Check if there's too much movement during calibration
    double maxAllowedVariance =
        2.0; // m/s² - increased threshold for car vibration
    bool isStable = maxVarianceX <= maxAllowedVariance &&
        maxVarianceY <= maxAllowedVariance &&
        maxVarianceZ <= maxAllowedVariance;

    if (!isStable) {
      print('Warning: Device movement detected during orientation calibration');
      print('Orientation detection might be less accurate');
    }

    // Apply low-pass filter to mean values
    if (_isFirstReading) {
      _filteredAccel = meanValues;
      _isFirstReading = false;
    } else {
      for (int i = 0; i < 3; i++) {
        _filteredAccel[i] =
            _alpha * _filteredAccel[i] + (1 - _alpha) * meanValues[i];
      }
    }

    // Store the filtered offsets
    _sensorOffsets['accel'] = List.from(_filteredAccel);

    // Calculate magnitude of filtered values
    double magnitude = sqrt(_filteredAccel[0] * _filteredAccel[0] +
        _filteredAccel[1] * _filteredAccel[1] +
        _filteredAccel[2] * _filteredAccel[2]);

    // Normalize relative to gravity
    List<double> normalizedAccel = List.from(_filteredAccel);
    if (magnitude > 0.1) {
      // Avoid division by very small numbers
      for (int i = 0; i < 3; i++) {
        normalizedAccel[i] = normalizedAccel[i] / magnitude * 9.81;
      }
    }

    // Get absolute values for comparison
    double absX = normalizedAccel[0].abs();
    double absY = normalizedAccel[1].abs();
    double absZ = normalizedAccel[2].abs();

    // Find maximum acceleration component
    double maxAcc = max(max(absX, absY), absZ);

    // Calculate confidence as percentage of gravity
    _orientationConfidence = (maxAcc / 9.81) * 100;

    // Determine orientation with hysteresis to prevent flipping
    double threshold = 6.0; // About 60% of gravity
    String newOrientation;

    if (absZ > threshold && absZ >= absX && absZ >= absY) {
      newOrientation = normalizedAccel[2] > 0 ? 'face_up' : 'face_down';
    } else if (absX >= threshold && absX >= absY) {
      newOrientation =
          normalizedAccel[0] > 0 ? 'landscape_left' : 'landscape_right';
    } else if (absY >= threshold) {
      newOrientation = normalizedAccel[1] > 0 ? 'portrait' : 'portrait_down';
    } else {
      // If no clear orientation, keep previous orientation but with low confidence
      newOrientation = _deviceOrientation
          .split('_')[0]; // Remove any existing uncertainty marker
      _orientationConfidence =
          min(_orientationConfidence, 50.0); // Cap confidence at 50%
    }

    // Set the initial orientation - this will remain fixed for the recording session
    if (_deviceOrientation == 'unknown' || _orientationConfidence > 60.0) {
      _deviceOrientation = newOrientation;
      print(
          'Initial device orientation detected: $_deviceOrientation (Confidence: ${_orientationConfidence.toStringAsFixed(1)}%)');
      if (_orientationConfidence < 80.0) {
        print('Warning: Low confidence in orientation detection.');
        print(
            'Ensure the device is firmly mounted and try starting recording again.');
      }
      // Notify about calibration progress
      onCalibrationComplete?.call(
          _deviceOrientation, _orientationConfidence, _sensorOffsets);
    }

    if (_calibrationGyroData.isNotEmpty) {
      // Calculate gyroscope offsets (average of readings)
      double sumX = 0, sumY = 0, sumZ = 0;
      for (var event in _calibrationGyroData) {
        sumX += event.x;
        sumY += event.y;
        sumZ += event.z;
      }
      _sensorOffsets['gyro'] = [
        sumX / _calibrationGyroData.length,
        sumY / _calibrationGyroData.length,
        sumZ / _calibrationGyroData.length
      ];
    }
  }

  void _processGyroData() {
    if (_calibrationGyroData.isEmpty) return;

    // Calculate gyroscope offsets (average of readings)
    double sumX = 0, sumY = 0, sumZ = 0;
    for (var event in _calibrationGyroData) {
      sumX += event.x;
      sumY += event.y;
      sumZ += event.z;
    }
    _sensorOffsets['gyro'] = [
      sumX / _calibrationGyroData.length,
      sumY / _calibrationGyroData.length,
      sumZ / _calibrationGyroData.length
    ];

    // Notify about calibration progress
    onCalibrationComplete?.call(
        _deviceOrientation, _orientationConfidence, _sensorOffsets);
  }

  void dispose() {
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _samplingTimer?.cancel();
  }
}
