import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:csv/csv.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:device_info_plus/device_info_plus.dart';

class SensorService {
  List<List<dynamic>> _sensorData = [];
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _gpsTimer;
  bool _isRecording = false;
  DateTime? _startTime;
  DateTime? _recordingStartTime;

  // Timestamp tracking for precise sampling rate calculation
  List<int> _accelerometerTimestamps = [];
  List<int> _gyroscopeTimestamps = [];

  // Timer to enforce 100Hz sampling
  Timer? _accelerometerTimer;
  Timer? _gyroscopeTimer;
  static const int _targetSamplingIntervalMs = 10; // 100Hz = 10ms interval

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

  // Last sensor readings to ensure fixed rate
  AccelerometerEvent? _lastAccelEvent;
  GyroscopeEvent? _lastGyroEvent;
  Position? _lastPosition;

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

    // Add header with metadata and annotation columns
    _sensorData.add([
      'timestamp_ms',
      'sensor_type',
      'x',
      'y',
      'z',
      'magnitude',
      'is_pothole',
      'user_feedback',
      'latitude',      // GPS data
      'longitude',
      'altitude',
      'speed',
      'recording_start_time',
      DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(_recordingStartTime!),
    ]);

    try {
      // Start accelerometer recording with fixed timing
      _accelerometerSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
        _lastAccelEvent = event; // Save the most recent event
      });

      // Set up timer to read at exactly 100Hz
      _accelerometerTimer = Timer.periodic(Duration(milliseconds: _targetSamplingIntervalMs), (timer) {
        if (_isRecording && _lastAccelEvent != null) {
          final now = DateTime.now();
          final timestamp = now.difference(_startTime!).inMilliseconds;
          _accelerometerTimestamps.add(timestamp);

          // Calculate magnitude for detection
          final magnitude = sqrt(_lastAccelEvent!.x * _lastAccelEvent!.x +
              _lastAccelEvent!.y * _lastAccelEvent!.y +
              _lastAccelEvent!.z * _lastAccelEvent!.z);

          // Process for bump detection
          _processBumpDetection(_lastAccelEvent!, magnitude, now);

          _sensorData.add([
            timestamp,
            'accelerometer',
            _lastAccelEvent!.x,
            _lastAccelEvent!.y,
            _lastAccelEvent!.z,
            magnitude,
            '',  // is_pothole (will be filled later)
            '',  // user_feedback (will be filled later)
            _lastPosition?.latitude ?? '',  // GPS data
            _lastPosition?.longitude ?? '',
            _lastPosition?.altitude ?? '',
            _lastPosition?.speed ?? '',
            '',  // empty for other columns
          ]);
        }
      });
    } catch (e) {
      print("Failed to initialize accelerometer: $e");
    }

    try {
      // Start gyroscope recording with fixed timing
      _gyroscopeSubscription = gyroscopeEvents.listen((GyroscopeEvent event) {
        _lastGyroEvent = event; // Save the most recent event
      });

      // Set up timer to read at exactly 100Hz
      _gyroscopeTimer = Timer.periodic(Duration(milliseconds: _targetSamplingIntervalMs), (timer) {
        if (_isRecording && _lastGyroEvent != null) {
          final now = DateTime.now();
          final timestamp = now.difference(_startTime!).inMilliseconds;
          _gyroscopeTimestamps.add(timestamp);

          _sensorData.add([
            timestamp,
            'gyroscope',
            _lastGyroEvent!.x,
            _lastGyroEvent!.y,
            _lastGyroEvent!.z,
            '',  // magnitude (only for accelerometer)
            '',  // is_pothole
            '',  // user_feedback
            _lastPosition?.latitude ?? '',  // GPS data
            _lastPosition?.longitude ?? '',
            _lastPosition?.altitude ?? '',
            _lastPosition?.speed ?? '',
            '',  // empty for other columns
          ]);
        }
      });
    } catch (e) {
      print("Failed to initialize gyroscope: $e");
    }

    // Start GPS recording every 10 seconds
    try {
      _startGPSTracking();

      // Record GPS position every 10 seconds
      _gpsTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
        if (_isRecording && _lastPosition != null) {
          final timestamp = DateTime.now().difference(_startTime!).inMilliseconds;

          _sensorData.add([
            timestamp,
            'gps',
            '',  // x
            '',  // y
            '',  // z
            '',  // magnitude
            '',  // is_pothole
            '',  // user_feedback
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            _lastPosition!.altitude,
            _lastPosition!.speed,
            '',  // empty for other columns
          ]);
        }
      });
    } catch (e) {
      print("Failed to initialize GPS tracking: $e");
    }
  }

  // Start GPS position streaming
  Future<void> _startGPSTracking() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Location services are disabled');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Location permissions are denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('Location permissions are permanently denied');
        return;
      }

      // Get initial position
      Position position = await Geolocator.getCurrentPosition();
      _lastPosition = position;

      // Listen for position updates
      _positionSubscription = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          )
      ).listen((Position position) {
        _lastPosition = position;
      });
    } catch (e) {
      print("Error starting GPS tracking: $e");
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

  // Calculate actual sampling rate from timestamp data
  double _calculateActualSamplingRate(List<int> timestamps) {
    if (timestamps.length < 2) return 0;

    // Calculate time differences between consecutive samples
    List<int> intervals = [];
    for (int i = 1; i < timestamps.length; i++) {
      intervals.add(timestamps[i] - timestamps[i-1]);
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
    await _positionSubscription?.cancel();
    _accelerometerTimer?.cancel();
    _gyroscopeTimer?.cancel();
    _gpsTimer?.cancel();

    // Calculate actual sampling rates
    double accelSamplingRate = _calculateActualSamplingRate(_accelerometerTimestamps);
    double gyroSamplingRate = _calculateActualSamplingRate(_gyroscopeTimestamps);

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
      '',
      '',
      '',
      '',
    ]);

    // Add device info
    Map<String, dynamic> deviceData = await _getDeviceInfo();
    _sensorData.add(['device_info', '', '', '', '', '', '', '', '', '', '', '', '']);

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
        '',
        '',
        '',
        '',
      ]);
    });

    // Apply annotations to the data
    for (int i = 1; i < _sensorData.length; i++) {
      var row = _sensorData[i];

      // Skip metadata rows
      if (row[1] != 'accelerometer' && row[1] != 'gyroscope' && row[1] != 'gps') {
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
    _positionSubscription?.cancel();
    _accelerometerTimer?.cancel();
    _gyroscopeTimer?.cancel();
    _gpsTimer?.cancel();
  }
}

double abs(double value) {
  return value < 0 ? -value : value;
}