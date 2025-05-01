import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class CalibrationPopup extends StatefulWidget {
  final String orientation;
  final double orientationConfidence;
  final Map<String, List<double>> sensorOffsets;
  final VoidCallback onCalibrationComplete;
  final bool isLandscape;

  const CalibrationPopup({
    Key? key,
    required this.orientation,
    required this.orientationConfidence,
    required this.sensorOffsets,
    required this.onCalibrationComplete,
    this.isLandscape = false,
  }) : super(key: key);

  @override
  State<CalibrationPopup> createState() => _CalibrationPopupState();
}

class _CalibrationPopupState extends State<CalibrationPopup> with SingleTickerProviderStateMixin {
  late AnimationController _progressController;
  final List<bool> _checks = [false, false, false, false];
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..addListener(() {
        setState(() {
          // Update checks based on progress
          if (_progressController.value > 0.25 && !_checks[0]) {
            _checks[0] = true;
            _currentStep = 1;
          }
          if (_progressController.value > 0.5 && !_checks[1]) {
            _checks[1] = true;
            _currentStep = 2;
          }
          if (_progressController.value > 0.75 && !_checks[2]) {
            _checks[2] = true;
            _currentStep = 3;
          }
          if (_progressController.value >= 1.0 && !_checks[3]) {
            _checks[3] = true;
            _currentStep = 4;
            widget.onCalibrationComplete();
          }
        });
      });

    _progressController.forward();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  String _getOrientationText() {
    switch (widget.orientation) {
      case 'landscape_left':
        return 'Landscape Left';
      case 'landscape_right':
        return 'Landscape Right';
      case 'portrait':
        return 'Portrait';
      case 'portrait_down':
        return 'Portrait Down';
      case 'face_up':
        return 'Face Up';
      case 'face_down':
        return 'Face Down';
      default:
        return 'Unknown';
    }
  }

  Widget _buildCheckItem(String text, bool checked, bool current) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: widget.isLandscape ? 2.h : 4.h),
      child: Row(
        children: [
          Container(
            width: widget.isLandscape ? 20.w : 24.w,
            height: widget.isLandscape ? 20.h : 24.h,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: checked ? Colors.green : (current ? Colors.blue : Colors.grey.shade300),
            ),
            child: checked
                ? Icon(Icons.check, color: Colors.white, size: widget.isLandscape ? 14 : 16)
                : (current ? const CircularProgressIndicator(color: Colors.white) : null),
          ),
          SizedBox(width: widget.isLandscape ? 8.w : 12.w),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: widget.isLandscape ? 12.sp : 14.sp,
                color: checked ? Colors.green : (current ? Colors.blue : Colors.grey.shade700),
                fontWeight: current ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: widget.isLandscape ? 600.w : 400.w,
            maxHeight: widget.isLandscape ? 300.h : 500.h,
          ),
          child: Card(
            margin: EdgeInsets.all(widget.isLandscape ? 16.r : 24.r),
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(16.r),
                child: widget.isLandscape
                    ? _buildLandscapeLayout()
                    : _buildPortraitLayout(),
              ),
            ),
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
          'Calibrating Sensors',
          style: TextStyle(
            fontSize: widget.isLandscape ? 16.sp : 18.sp,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: widget.isLandscape ? 8.h : 16.h),
        LinearProgressIndicator(
          value: _progressController.value,
          backgroundColor: Colors.grey.shade200,
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
        ),
        SizedBox(height: widget.isLandscape ? 16.h : 24.h),
        _buildCheckItem(
          'Initializing sensors...',
          _checks[0],
          _currentStep == 0,
        ),
        _buildCheckItem(
          'Detecting orientation: ${_getOrientationText()}\n'
          'Confidence: ${widget.orientationConfidence.toStringAsFixed(1)}%',
          _checks[1],
          _currentStep == 1,
        ),
        _buildCheckItem(
          'Calculating accelerometer offsets:\n'
          'X: ${widget.sensorOffsets['accel']![0].toStringAsFixed(3)}\n'
          'Y: ${widget.sensorOffsets['accel']![1].toStringAsFixed(3)}\n'
          'Z: ${widget.sensorOffsets['accel']![2].toStringAsFixed(3)}',
          _checks[2],
          _currentStep == 2,
        ),
        _buildCheckItem(
          'Calculating gyroscope offsets:\n'
          'X: ${widget.sensorOffsets['gyro']![0].toStringAsFixed(3)}\n'
          'Y: ${widget.sensorOffsets['gyro']![1].toStringAsFixed(3)}\n'
          'Z: ${widget.sensorOffsets['gyro']![2].toStringAsFixed(3)}',
          _checks[3],
          _currentStep == 3,
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 1,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Calibrating Sensors',
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 6.h),
              LinearProgressIndicator(
                value: _progressController.value,
                backgroundColor: Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
              SizedBox(height: 12.h),
              _buildCheckItem(
                'Initializing sensors...',
                _checks[0],
                _currentStep == 0,
              ),
              _buildCheckItem(
                'Detecting orientation: ${_getOrientationText()}',
                _checks[1],
                _currentStep == 1,
              ),
            ],
          ),
        ),
        SizedBox(width: 12.w),
        Expanded(
          flex: 1,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCheckItem(
                'Accelerometer offsets:\n'
                'X: ${widget.sensorOffsets['accel']![0].toStringAsFixed(3)}\n'
                'Y: ${widget.sensorOffsets['accel']![1].toStringAsFixed(3)}\n'
                'Z: ${widget.sensorOffsets['accel']![2].toStringAsFixed(3)}',
                _checks[2],
                _currentStep == 2,
              ),
              _buildCheckItem(
                'Gyroscope offsets:\n'
                'X: ${widget.sensorOffsets['gyro']![0].toStringAsFixed(3)}\n'
                'Y: ${widget.sensorOffsets['gyro']![1].toStringAsFixed(3)}\n'
                'Z: ${widget.sensorOffsets['gyro']![2].toStringAsFixed(3)}',
                _checks[3],
                _currentStep == 3,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
