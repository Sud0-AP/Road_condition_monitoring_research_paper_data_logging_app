import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';

class FileUtils {
  // Export recording files to Downloads folder
  static Future<String?> exportRecordingToDownloads(String videoPath, String csvPath) async {
    try {
      // Check for storage permission
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
        if (!status.isGranted) {
          return null;
        }
      }

      // Create downloads directory
      final downloadsDir = Directory('/storage/emulated/0/Download/PotholeDetector');
      if (!await downloadsDir.exists()) {
        try {
          await downloadsDir.create(recursive: true);
        } catch (e) {
          print('Error creating directory: $e');
          // Try alternative method for Android 10+
          final tempDir = await getTemporaryDirectory();
          final tempDownloadsDir = Directory('${tempDir.path}/PotholeDetector');
          if (!await tempDownloadsDir.exists()) {
            await tempDownloadsDir.create(recursive: true);
          }

          // Copy files to temp dir
          final videoFile = File(videoPath);
          final csvFile = File(csvPath);

          if (await videoFile.exists()) {
            final videoFileName = videoPath.split('/').last;
            await videoFile.copy('${tempDownloadsDir.path}/$videoFileName');
          }

          if (await csvFile.exists()) {
            final csvFileName = csvPath.split('/').last;
            await csvFile.copy('${tempDownloadsDir.path}/$csvFileName');
          }

          return tempDownloadsDir.path;
        }
      }

      // If directory creation succeeded, copy files
      final videoFile = File(videoPath);
      final csvFile = File(csvPath);

      if (await videoFile.exists()) {
        final videoFileName = videoPath.split('/').last;
        final videoDestPath = '${downloadsDir.path}/$videoFileName';
        await videoFile.copy(videoDestPath);
      }

      if (await csvFile.exists()) {
        final csvFileName = csvPath.split('/').last;
        final csvDestPath = '${downloadsDir.path}/$csvFileName';
        await csvFile.copy(csvDestPath);
      }

      return downloadsDir.path;
    } catch (e) {
      print('Error exporting files: $e');
      return null;
    }
  }

  // Open file manager to Downloads folder
  static Future<bool> openDownloadsFolder() async {
    try {
      final Uri uri = Uri.parse('content://com.android.externalstorage.documents/document/primary%3ADownload%2FPotholeDetector');

      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri);
      }

      // Try a more generic approach
      final Uri fallbackUri = Uri.parse('file:///storage/emulated/0/Download/PotholeDetector');
      if (await canLaunchUrl(fallbackUri)) {
        return await launchUrl(fallbackUri);
      }

      return false;
    } catch (e) {
      print('Error opening downloads folder: $e');
      return false;
    }
  }

  static Future<bool> openFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        print('File does not exist: $filePath');
        return false;
      }

      // For video files, try to use intent with MIME type
      if (filePath.toLowerCase().endsWith('.mp4')) {
        final uri = Uri.file(filePath);
        return await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      }

      // For CSV files, export to downloads and then try to open
      if (filePath.toLowerCase().endsWith('.csv')) {
        final downloadsDir = Directory('/storage/emulated/0/Download/PotholeDetector');
        if (!await downloadsDir.exists()) {
          await downloadsDir.create(recursive: true);
        }

        final fileName = filePath.split('/').last;
        final destPath = '${downloadsDir.path}/$fileName';

        await file.copy(destPath);

        // Try to launch the exported file
        final uri = Uri.file(destPath);
        return await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      }

      return false;
    } catch (e) {
      print('Error opening file: $e');
      return false;
    }
  }

  // Show exported files info
  static void showExportedFilesInfo(BuildContext context, String exportPath) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Files Exported'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Files have been exported to:'),
              const SizedBox(height: 8),
              Text(
                exportPath,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'You can access these files using any file manager app. '
                    'Navigate to your Downloads folder and look for the PotholeDetector directory.',
              ),
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
}
