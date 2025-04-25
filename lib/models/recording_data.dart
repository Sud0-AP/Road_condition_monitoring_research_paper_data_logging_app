class RecordingData {
  final String id;
  final String videoPath;
  final String sensorDataPath;
  final DateTime timestamp;

  RecordingData({
    required this.id,
    required this.videoPath,
    required this.sensorDataPath,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'videoPath': videoPath,
      'sensorDataPath': sensorDataPath,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory RecordingData.fromMap(Map<String, dynamic> map) {
    return RecordingData(
      id: map['id'],
      videoPath: map['videoPath'],
      sensorDataPath: map['sensorDataPath'],
      timestamp: DateTime.parse(map['timestamp']),
    );
  }
}
