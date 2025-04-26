import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class PotholePromptOverlay extends StatefulWidget {
  final Function(bool isPothole) onResponse;
  final Function() onTimeout;
  final bool isLandscape;

  const PotholePromptOverlay({
    Key? key,
    required this.onResponse,
    required this.onTimeout,
    this.isLandscape = false,
  }) : super(key: key);

  @override
  State<PotholePromptOverlay> createState() => _PotholePromptOverlayState();
}

class _PotholePromptOverlayState extends State<PotholePromptOverlay> {
  late Timer _timer;
  int _secondsLeft = 10;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsLeft--;
      });

      if (_secondsLeft <= 0) {
        _timer.cancel();
        widget.onTimeout();
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Card(
          margin: EdgeInsets.all(widget.isLandscape ? 40.r : 24.r),
          child: Padding(
            padding: EdgeInsets.all(16.r),
            child: widget.isLandscape
                ? _buildLandscapeLayout()
                : _buildPortraitLayout(),
          ),
        ),
      ),
    );
  }

  Widget _buildPortraitLayout() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Pothole Detected?',
          style: TextStyle(
            fontSize: 24.sp,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 16.h),
        Text(
          'Was that bump a pothole?',
          style: TextStyle(fontSize: 16.sp),
        ),
        SizedBox(height: 24.h),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton(
              onPressed: () => widget.onResponse(false),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey,
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              ),
              child: const Text('Not a Pothole'),
            ),
            ElevatedButton(
              onPressed: () => widget.onResponse(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              ),
              child: const Text('Yes, Pothole'),
            ),
          ],
        ),
        SizedBox(height: 16.h),
        Text(
          'Auto-dismissing in $_secondsLeft seconds...',
          style: TextStyle(
            fontSize: 14.sp,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pothole Detected?',
                style: TextStyle(
                  fontSize: 22.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                'Was that bump a pothole?',
                style: TextStyle(fontSize: 14.sp),
              ),
              SizedBox(height: 8.h),
              Text(
                'Auto-dismissing in $_secondsLeft seconds...',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: 16.w),
        Expanded(
          flex: 2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: () => widget.onResponse(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  minimumSize: Size(double.infinity, 60.h),  // Increased height even more
                  padding: EdgeInsets.symmetric(vertical: 16.h),  // Increased padding
                ),
                child: Text('Yes, Pothole', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
              ),
              SizedBox(height: 20.h),  // Increased spacing more
              ElevatedButton(
                onPressed: () => widget.onResponse(false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey,
                  minimumSize: Size(double.infinity, 60.h),  // Increased height even more
                  padding: EdgeInsets.symmetric(vertical: 16.h),  // Increased padding
                ),
                child: Text('Not a Pothole', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
