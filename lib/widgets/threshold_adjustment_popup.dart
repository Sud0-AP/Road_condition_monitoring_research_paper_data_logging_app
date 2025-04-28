import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ThresholdAdjustmentPopup extends StatefulWidget {
  final double currentThreshold;
  final Function(double) onThresholdChanged;
  final bool isLandscape;

  const ThresholdAdjustmentPopup({
    super.key,
    required this.currentThreshold,
    required this.onThresholdChanged,
    this.isLandscape = false,
  });

  @override
  State<ThresholdAdjustmentPopup> createState() => _ThresholdAdjustmentPopupState();
}

class _ThresholdAdjustmentPopupState extends State<ThresholdAdjustmentPopup> {
  late double _threshold;

  @override
  void initState() {
    super.initState();
    _threshold = widget.currentThreshold;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Bump Detection Settings',
        style: TextStyle(fontSize: widget.isLandscape ? 18.sp : 20.sp),
      ),
      content: SizedBox(
        width: widget.isLandscape ? 300.w : 280.w,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Bump Sensitivity Threshold',
              style: TextStyle(fontSize: widget.isLandscape ? 14.sp : 16.sp),
            ),
            SizedBox(height: 8.h),
            Row(
              children: [
                Text('Low', style: TextStyle(fontSize: 12.sp)),
                Expanded(
                  child: Slider(
                    value: _threshold,
                    min: 1.0,
                    max: 10.0,
                    divisions: 18,
                    label: _threshold.toStringAsFixed(1),
                    onChanged: (value) {
                      setState(() {
                        _threshold = value;
                      });
                    },
                  ),
                ),
                Text('High', style: TextStyle(fontSize: 12.sp)),
              ],
            ),
            SizedBox(height: 8.h),
            Text(
              'Current: ${_threshold.toStringAsFixed(1)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: widget.isLandscape ? 14.sp : 16.sp,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Lower values increase sensitivity (more bump detections).\n'
                  'Higher values decrease sensitivity (fewer detections).',
              style: TextStyle(fontSize: 12.sp, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            widget.onThresholdChanged(_threshold);
            Navigator.pop(context);
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}