import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/recording_data.dart';

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({Key? key}) : super(key: key);

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  List<RecordingData> _recordings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  Future<void> _loadRecordings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load recordings directly from Downloads folder
      final downloadsDir = Directory('/storage/emulated/0/Download/PotholeDetector');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      final List<FileSystemEntity> entities = await downloadsDir.list().toList();
      final List<RecordingData> recordings = [];

      for (var entity in entities) {
        if (entity is Directory && entity.path.contains('Recording_')) {
          final recordingId = entity.path.split('/').last;
          final videoFile = File('${entity.path}/video.mp4');
          final sensorFile = File('${entity.path}/sensor_data.csv');

          if (await videoFile.exists() && await sensorFile.exists()) {
            // Parse timestamp from folder name
            final dateString = recordingId.replaceAll('Recording_', '');
            DateTime timestamp;
            try {
              timestamp = DateFormat('yyyyMMdd_HHmmss').parse(dateString);
            } catch (e) {
              timestamp = await videoFile.lastModified();
            }

            recordings.add(RecordingData(
              id: recordingId,
              videoPath: videoFile.path,
              sensorDataPath: sensorFile.path,
              timestamp: timestamp,
            ));
          }
        }
      }

      // Sort by timestamp (newest first)
      recordings.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      setState(() {
        _recordings = recordings;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading recordings: $e')),
      );
    }
  }

  // Share recording files
  Future<void> _shareRecording(RecordingData recording) async {
    try {
      final videoFile = File(recording.videoPath);
      final sensorFile = File(recording.sensorDataPath);

      // First check if files exist
      bool videoExists = await videoFile.exists();
      bool sensorExists = await sensorFile.exists();

      if (!videoExists && !sensorExists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No files found to share')),
        );
        return;
      }

      // Prepare list of files to share
      List<XFile> filesToShare = [];

      if (videoExists) {
        filesToShare.add(XFile(videoFile.path));
      }

      if (sensorExists) {
        filesToShare.add(XFile(sensorFile.path));
      }

      // Share all files at once
      await Share.shareXFiles(
        filesToShare,
        subject: 'Pothole Recording',
        text: 'Pothole recording from ${DateFormat('MMM dd, yyyy - HH:mm').format(recording.timestamp)}',
      );
    } catch (e) {
      print('Error sharing files: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing files: $e')),
      );
    }
  }

  // View files directly
  Future<void> _viewFiles(RecordingData recording) async {
    try {
      // Try to open the folder containing the files
      final directory = Directory(recording.videoPath).parent;
      final uri = Uri.parse('content://com.android.externalstorage.documents/document/primary%3ADownload%2FPotholeDetector%2F${directory.path.split('/').last}');

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        // Fallback: try to open the Downloads/PotholeDetector folder
        final baseUri = Uri.parse('content://com.android.externalstorage.documents/document/primary%3ADownload%2FPotholeDetector');
        if (await canLaunchUrl(baseUri)) {
          await launchUrl(baseUri);
        } else {
          // Last resort: show info about the files
          if (!mounted) return;
          _showFileInfo(recording);
        }
      }
    } catch (e) {
      print('Error viewing files: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening files: $e')),
      );
    }
  }

  // Show file info
  Future<void> _showFileInfo(RecordingData recording) async {
    final videoFile = File(recording.videoPath);
    final sensorFile = File(recording.sensorDataPath);

    String videoExists = await videoFile.exists() ? "Yes" : "No";
    String sensorExists = await sensorFile.exists() ? "Yes" : "No";

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recording Files'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Video file exists: $videoExists'),
              SizedBox(height: 8.h),
              Text('Video path: ${recording.videoPath}'),
              SizedBox(height: 16.h),
              Text('Sensor data exists: $sensorExists'),
              SizedBox(height: 8.h),
              Text('Sensor data path: ${recording.sensorDataPath}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Open the main Downloads/PotholeDetector folder
  Future<void> _openDownloadsFolder() async {
    try {
      final uri = Uri.parse('content://com.android.externalstorage.documents/document/primary%3ADownload%2FPotholeDetector');

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open Downloads folder. Files are located in /Download/PotholeDetector/'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      print('Error opening downloads folder: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening Downloads folder: $e')),
      );
    }
  }

  Future<void> _deleteRecording(RecordingData recording) async {
    try {
      final directory = Directory(recording.videoPath).parent;
      await directory.delete(recursive: true);

      setState(() {
        _recordings.removeWhere((r) => r.id == recording.id);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recording deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting recording: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recordings'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.folder),
            onPressed: _openDownloadsFolder,
            tooltip: 'Open Downloads Folder',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRecordings,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _recordings.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off, size: 64.sp, color: Colors.grey),
            SizedBox(height: 16.h),
            Text(
              'No recordings yet',
              style: TextStyle(fontSize: 18.sp, color: Colors.grey),
            ),
            SizedBox(height: 24.h),
            ElevatedButton(
              onPressed: _openDownloadsFolder,
              child: const Text('Open Downloads Folder'),
            ),
          ],
        ),
      )
          : ListView.builder(
        itemCount: _recordings.length,
        itemBuilder: (context, index) {
          final recording = _recordings[index];
          final date = DateFormat('MMM dd, yyyy - HH:mm')
              .format(recording.timestamp);

          return Card(
            margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            elevation: 2,
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.all(12.r),
                  leading: Container(
                    width: 60.w,
                    height: 60.h,
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Icon(Icons.video_file, size: 32.sp),
                  ),
                  title: Text(
                    'Recording ${index + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16.sp,
                    ),
                  ),
                  subtitle: Text(date),
                  onTap: () => _viewFiles(recording),
                ),
                Padding(
                  padding: EdgeInsets.only(bottom: 12.h, left: 8.w, right: 8.w),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _actionButton(
                        icon: Icons.folder_open,
                        label: 'Open',
                        onPressed: () => _viewFiles(recording),
                      ),
                      _actionButton(
                        icon: Icons.share,
                        label: 'Share',
                        onPressed: () => _shareRecording(recording),
                      ),
                      _actionButton(
                        icon: Icons.delete,
                        label: 'Delete',
                        onPressed: () => _deleteRecording(recording),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8.r),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24.sp),
            SizedBox(height: 4.h),
            Text(
              label,
              style: TextStyle(fontSize: 12.sp),
            ),
          ],
        ),
      ),
    );
  }
}
