import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/recording_data.dart';

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

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

  Future<Directory?> _getRecordingsBaseDirectory() async {
    if (Platform.isAndroid) {
      //Downloads path on Android
      const downloadsPath = '/storage/emulated/0/Download/PotholeDetectorRecordings';
      final dir = Directory(downloadsPath);
      final downloadsBase = Directory('/storage/emulated/0/Download');
      if(!await downloadsBase.exists()){
        print("Downloads folder '/storage/emulated/0/Download' might not be accessible.");
      }
      return dir;
    } else {
      //application documents directory for iOS
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      return Directory(path.join(appDocDir.path, 'PotholeDetectorRecordings'));
    }
  }


  Future<void> _loadRecordings() async {
    if (!mounted) return;
    setState(() { _isLoading = true; });

    try {
      final Directory? baseDir = await _getRecordingsBaseDirectory();

      if (baseDir == null) {
        print("Could not determine recordings directory.");
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not access storage location.')));
          setState(() { _recordings = []; _isLoading = false; });
        }
        return;
      }

      print('Checking base directory: ${baseDir.path}');

      if (!await baseDir.exists()) {
        print('Recordings base directory does not exist: ${baseDir.path}');
        if(mounted) setState(() { _recordings = []; _isLoading = false; });
        return;
      }

      List<FileSystemEntity> entities;
      try {
        entities = await baseDir.list().toList();
      } catch (e) {
        print("Error listing directory ${baseDir.path}: $e");
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error accessing recordings folder: $e')));
          setState(() { _recordings = []; _isLoading = false; });
        }
        return;
      }

      final List<RecordingData> loadedRecordings = [];
      print('Found ${entities.length} entities in ${baseDir.path}');

      for (var entity in entities) {
        if (entity is Directory && path.basename(entity.path).startsWith('Recording_')) {
          final recordingFolderName = path.basename(entity.path);
          final videoFile = File(path.join(entity.path, 'video.mp4'));
          final sensorFile = File(path.join(entity.path, 'sensor_data.csv'));
          bool videoExists = await videoFile.exists();
          bool sensorExists = await sensorFile.exists();

          print('Checking folder: ${entity.path} - Video: $videoExists, Sensor: $sensorExists');

          if (videoExists || sensorExists) {
            final dateString = recordingFolderName.replaceFirst('Recording_', '');
            DateTime timestamp;
            try {
              timestamp = DateFormat('yyyyMMdd_HHmmss').parse(dateString);
            } catch (e) {
              print('Error parsing timestamp from folder name $recordingFolderName: $e');
              try {
                if (videoExists) { timestamp = await videoFile.lastModified(); }
                else if (sensorExists) { timestamp = await sensorFile.lastModified(); }
                else { timestamp = DateTime.now(); }
              } catch (modError) {
                print('Error getting file modification time for ${entity.path}: $modError');
                timestamp = DateTime.now();
              }
            }
            loadedRecordings.add(RecordingData(
              id: recordingFolderName,
              videoPath: videoFile.path,
              sensorDataPath: sensorFile.path,
              timestamp: timestamp,
            ));
          } else {
            print('Skipping empty/invalid folder: ${entity.path}');
          }
        }
      }

      loadedRecordings.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if(mounted) {
        setState(() { _recordings = loadedRecordings; _isLoading = false; });
      }
      print('Loaded ${_recordings.length} valid recordings');

    } catch (e, stacktrace) {
      print('Error loading recordings: $e\n$stacktrace');
      if(mounted) {
        setState(() { _isLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('Error loading recordings: $e')), );
      }
    }
  }

  // Share recording files
  Future<void> _shareRecording(RecordingData recording) async {
    try {
      final videoFile = File(recording.videoPath);
      final sensorFile = File(recording.sensorDataPath);
      bool videoExists = await videoFile.exists();
      bool sensorExists = await sensorFile.exists();
      if (!videoExists && !sensorExists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text('No files found to share')), );
        return;
      }
      List<XFile> filesToShare = [];
      if (videoExists) filesToShare.add(XFile(videoFile.path));
      if (sensorExists) filesToShare.add(XFile(sensorFile.path));
      if (filesToShare.isNotEmpty) {
        await Share.shareXFiles( filesToShare, subject: 'Pothole Recording Data', text: 'Pothole recording data from ${DateFormat('MMM dd, yyyy - HH:mm').format(recording.timestamp)}', );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text('No files found to share')), );
      }
    } catch (e) {
      print('Error sharing files: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('Error sharing files: $e')), );
    }
  }

  // Show file info and location
  Future<void> _showFileInfo(RecordingData recording) async {
    final videoFile = File(recording.videoPath);
    final sensorFile = File(recording.sensorDataPath);
    final directory = videoFile.parent;
    String videoExists = await videoFile.exists() ? "Yes" : "No";
    String sensorExists = await sensorFile.exists() ? "Yes" : "No";

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Recording Details'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Folder Location:', style: TextStyle(fontWeight: FontWeight.bold)),
                SelectableText(directory.path),
                if (Platform.isAndroid)
                  TextButton.icon(
                    icon: Icon(Icons.copy, size: 16.sp),
                    label: Text("Copy Path", style: TextStyle(fontSize: 12.sp)),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: directory.path));
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(content: Text('Path copied to clipboard'), duration: Duration(seconds: 1))
                      );
                    },
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 20)),
                  ),
                SizedBox(height: 16.h),
                const Text('Video File:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('Exists: $videoExists'),
                SelectableText('Path: ${recording.videoPath}'),
                SizedBox(height: 16.h),
                const Text('Sensor Data File:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('Exists: $sensorExists'),
                SelectableText('Path: ${recording.sensorDataPath}'),
              ],
            ),
          ),
          actions: [
            TextButton( onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'), ),
          ],
        );
      },
    );
  }

  // Open Recording Folder Android Only
  Future<void> _openRecordingFolder(RecordingData recording) async {
    if (!Platform.isAndroid) {
      print("Open folder is only supported on Android.");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Opening folder not supported on this platform.')),
      );
      return;
    }

    try {
      final directory = File(recording.videoPath).parent;
      final folderName = path.basename(directory.path);
      final uriString = 'content://com.android.externalstorage.documents/document/primary%3ADownload%2FPotholeDetectorRecordings%2F${Uri.encodeComponent(folderName)}';
      final uri = Uri.parse(uriString);

      print("Attempting to launch URI: $uriString");
      try {
        final bool launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!launched && mounted) {
          print("launchUrl returned false for $uriString");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open folder. No suitable file manager found?')),
          );
        }
      } catch (e) {
        print("Error launching URL $uriString: $e");
        print("Trying fallback to base folder...");
        const baseUriString = 'content://com.android.externalstorage.documents/document/primary%3ADownload%2FPotholeDetectorRecordings';
        final baseUri = Uri.parse(baseUriString);
        print("Fallback: Attempting to launch base URI: $baseUriString");
        try {
          final bool baseLaunched = await launchUrl(baseUri, mode: LaunchMode.externalApplication);
          if(!baseLaunched && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not open base folder. Please navigate manually.')),
            );
            _showFileInfo(recording); // Show info if boo boo happens
          }
        } catch (baseE) {
          print("Error launching base URL $baseUriString: $baseE");
          if(mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not open folder. Please navigate manually via a file manager.')),
            );
            _showFileInfo(recording); // Show info if boo boo happens
          }
        }
      }
    } catch (e) {
      print('Error trying to open folder: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening folder: $e')),
      );
    }
  }


  // Delete recording folder and its contents
  Future<void> _deleteRecording(RecordingData recording) async {
    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text('Are you sure you want to delete the recording from ${DateFormat('MMM dd, yyyy - HH:mm').format(recording.timestamp)}? This cannot be undone.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false), // User cancelled
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.of(dialogContext).pop(true), // User confirmed
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    // Proceed only if user confirmed
    if (confirmDelete == true) {
      try {
        final directory = File(recording.videoPath).parent; // Get the directory

        if (await directory.exists()) {
          await directory.delete(recursive: true);
          print('Deleted directory: ${directory.path}');

          // Update UI only after successful deletion
          if (mounted) {
            setState(() {
              _recordings.removeWhere((r) => r.id == recording.id);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Recording deleted')),
            );
          }
        } else {
          print('Directory not found, skipping deletion: ${directory.path}');
          if (mounted) {
            setState(() {
              _recordings.removeWhere((r) => r.id == recording.id);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Recording folder not found.')),
            );
          }
        }

      } catch (e) {
        print('Error deleting recording: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting recording: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recordings'),
        actions: [ IconButton( icon: const Icon(Icons.refresh), tooltip: 'Refresh Recordings', onPressed: _loadRecordings, ), ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _recordings.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off_outlined, size: 64.sp, color: Colors.grey[600]),
            SizedBox(height: 16.h),
            Text( 'No recordings found', style: TextStyle(fontSize: 18.sp, color: Colors.grey[600]), ),
            SizedBox(height: 8.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 40.w),
              child: Text(
                'Recordings saved in "Downloads/PotholeDetectorRecordings" (Android) or App Documents (iOS).',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.sp, color: Colors.grey[500]),
              ),
            ),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: _loadRecordings,
        child: ListView.builder(
          itemCount: _recordings.length,
          itemBuilder: (context, index) {
            final recording = _recordings[index];
            // *** Ensure 'date' is used ***
            final date = DateFormat('MMM dd, yyyy - HH:mm:ss')
                .format(recording.timestamp);
            return Card(
              margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              elevation: 2,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 16.w),
                    leading: Container(
                      width: 55.w, height: 55.h,
                      decoration: BoxDecoration( color: Theme.of(context).colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(8.r), ),
                      child: Icon( Icons.video_file_outlined, size: 30.sp, color: Theme.of(context).colorScheme.onSecondaryContainer, ),
                    ),
                    title: Text( recording.id, style: TextStyle( fontWeight: FontWeight.bold, fontSize: 15.sp, ), overflow: TextOverflow.ellipsis, ),
                    // *** Use 'date' here ***
                    subtitle: Text(date, style: TextStyle(fontSize: 13.sp)),
                    onTap: () => _showFileInfo(recording),
                  ),
                  Divider(height: 1.h, indent: 16.w, endIndent: 16.w),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 8.w),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (Platform.isAndroid)
                          _actionButton(
                            icon: Icons.folder_open_outlined,
                            label: 'Open Folder',
                            onPressed: () => _openRecordingFolder(recording),
                          ),
                        _actionButton(
                          icon: Icons.ios_share, // Platform-aware share icon
                          label: 'Share',
                          onPressed: () => _shareRecording(recording),
                        ),
                        _actionButton(
                          icon: Icons.delete_outline,
                          label: 'Delete',
                          color: Colors.redAccent,
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
      ),
    );
  }

  Widget _actionButton({ required IconData icon, required String label, required VoidCallback onPressed, Color? color, }) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.primary;
    return TextButton.icon(
      icon: Icon(icon, size: 22.sp, color: effectiveColor),
      label: Text( label, style: TextStyle(fontSize: 13.sp, color: effectiveColor), ),
      onPressed: onPressed,
      style: TextButton.styleFrom( padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)), ),
    );
  }
}