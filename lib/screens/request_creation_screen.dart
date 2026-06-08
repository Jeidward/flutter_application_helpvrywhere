import 'package:flutter/material.dart';
import '../services/request_service.dart';
import '../models/request_model.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';

class RequestCreationScreen extends StatefulWidget {
  const RequestCreationScreen({super.key});

  @override
  State<RequestCreationScreen> createState() => _RequestCreationScreenState();
}

class _RequestCreationScreenState extends State<RequestCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  final RequestService _service = RequestService();

  final AuthService _authService = AuthService();

  /// Data to complete the form
  final _titleController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _phoneController = TextEditingController();

  double? _latitude;
  double? _longitude;
  DateTime? _selectedDateTime;

  bool _isLoading = false;
  bool _isLocating = false;
  String? _error;
  String? lastCreatedId;

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> getLocation() async {
    setState(() {
      _isLocating = true;
      _error = null;
    });
    try {
      final position = await LocationService().getCurrentLocation();

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });
    } catch (e) {
      setState(() {
        _error = 'Impossible to obtain the position';
      });
    } finally {
      setState(() {
        _isLocating = false;
      });
    }
  }

  void clearLocation() {
    setState(() {
      _latitude = null;
      _longitude = null;
      _locationController.clear();
    });
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
    );

    if (pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (pickedTime == null) return;

    setState(() {
      _selectedDateTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  // CREATE
  Future<void> createRequest() async {
    if (!_formKey.currentState!.validate()) return;

    final user = _authService.currentUser;

    if (user == null) {
      setState(() {
        _error = 'User not logged in';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    if (_latitude == null || _longitude == null) {
      if (_locationController.text.trim().isEmpty) {
        setState(() {
          _error = 'Location required';
          _isLoading = false;
        });
        return;
      }

      try {
        final loc = await LocationService().getLocationFromAddress(
          _locationController.text.trim(),
        );

        _latitude = loc.latitude;
        _longitude = loc.longitude;
      } catch (e) {
        setState(() {
          _error = 'Invalid location';
          _isLoading = false;
        });
        return;
      }
    }
    try {
      final request = RequestModel(
        id: '',
        title: _titleController.text.trim(),
        category: _categoryController.text.trim(),
        description: _descriptionController.text.trim(),
        location: _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
        longitude: _longitude!,
        latitude: _latitude!,
        phone: _phoneController.text.trim(),
        dateTime: _selectedDateTime ?? DateTime.now(),
        createdAt: DateTime.now(),
        status: RequestStatus.active,
        userId: user!.uid,
      );

      final doc = await _service.createRequest(request);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Request created: ${doc.id}')));

      Navigator.pop(context);

      _formKey.currentState!.reset();
    } catch (e) {
      setState(() {
        _error = 'Failed to create request';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Create Request',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Ask a neighbour for help',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.darkNavy,
                  letterSpacing: -0.3,
                ),
              ),

              const SizedBox(height: 6),

              const Text(
                'Describe what you need and when you need it.',
                style: TextStyle(color: AppColors.muted, fontSize: 14),
              ),

              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: 'Title',
                        prefixIcon: const Icon(Icons.title),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.tile),
                        ),
                      ),
                      validator: (value) =>
                          value == null || value.isEmpty ? 'Required' : null,
                    ),

                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _categoryController,
                      decoration: InputDecoration(
                        labelText: 'Category',
                        prefixIcon: const Icon(Icons.category_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.tile),
                        ),
                      ),
                      validator: (value) =>
                          value == null || value.isEmpty ? 'Required' : null,
                    ),

                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Description',
                        prefixIcon: const Icon(Icons.notes),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.tile),
                        ),
                      ),
                      validator: (value) =>
                          value == null || value.isEmpty ? 'Required' : null,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _locationController,
                      decoration: InputDecoration(
                        labelText: 'Location',
                        prefixIcon: const Icon(Icons.location_on_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.tile),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLocating ? null : getLocation,
                        icon: _isLocating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location),
                        label: const Text('Get current position'),
                      ),
                    ),

                    const SizedBox(height: 8),

                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: (_latitude == null && _longitude == null)
                            ? null
                            : clearLocation,
                        icon: const Icon(Icons.close),
                        label: const Text('Remove location'),
                      ),
                    ),

                    if (_latitude != null && _longitude != null)
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.lightGreen,
                          borderRadius: BorderRadius.circular(AppRadius.tile),
                        ),
                        child: Row(
                          children: const [
                            Icon(
                              Icons.check_circle,
                              color: AppColors.primaryGreen,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Position detected',
                              style: TextStyle(
                                color: AppColors.primaryGreen,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    TextFormField(
                      readOnly: true,
                      controller: TextEditingController(
                        text: _selectedDateTime == null
                            ? 'Right now'
                            : '${_selectedDateTime!.day}/${_selectedDateTime!.month}/${_selectedDateTime!.year} '
                                  '${_selectedDateTime!.hour.toString().padLeft(2, '0')}:'
                                  '${_selectedDateTime!.minute.toString().padLeft(2, '0')}',
                      ),
                      decoration: InputDecoration(
                        labelText: 'Request date & time',
                        suffixIcon: const Icon(Icons.calendar_today),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.tile),
                        ),
                      ),
                      onTap: _pickDateTime,
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _selectedDateTime = null;
                        });
                      },
                      child: const Text('Right now'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Phone',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.tile),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(AppRadius.tile),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : createRequest,
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : const Text(
                          'Create Request',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
