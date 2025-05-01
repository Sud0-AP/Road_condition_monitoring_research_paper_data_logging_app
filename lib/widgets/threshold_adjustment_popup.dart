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
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: widget.isLandscape ? 500.w : 400.w,
          maxHeight: widget.isLandscape ? 250.h : 400.h,
        ),
        child: Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
          child: Padding(
            padding: EdgeInsets.all(16.r),
            child: widget.isLandscape ? _buildLandscapeLayout() : _buildPortraitLayout(),
          ),
        ),
      ),
    );
  }

  Widget _buildPortraitLayout() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
        Text(
          'Bump Detection Settings',
          style: TextStyle(
            fontSize: widget.isLandscape ? 16.sp : 20.sp,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 16.h),
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
        SizedBox(height: 16.h),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            SizedBox(width: 8.w),
            TextButton(
              onPressed: () {
                widget.onThresholdChanged(_threshold);
                Navigator.pop(context);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ],
    )
    );
  }

  Widget _buildLandscapeLayout() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Text(
          'Bump Detection Settings',
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 12.h),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bump Sensitivity Threshold',
                    style: TextStyle(fontSize: 14.sp),
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
                  Text(
                    'Current: ${_threshold.toStringAsFixed(1)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14.sp,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Note:',
                    style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    'Lower values increase sensitivity (more bump detections).\n'
                    'Higher values decrease sensitivity (fewer detections).',
                    style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 16.h),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            SizedBox(width: 8.w),
            TextButton(
              onPressed: () {
                widget.onThresholdChanged(_threshold);
                Navigator.pop(context);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ],
    )
    );
  }
}