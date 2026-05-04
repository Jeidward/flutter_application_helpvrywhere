import 'package:flutter/material.dart';
import '../services/request_service.dart';
import '../models/request_model.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';

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
  double? _latitude;
  double? _longitude;
  final _phoneController = TextEditingController();

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
        dateTime: DateTime.now(),
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
      appBar: AppBar(title: const Text('Create Request')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // TITLE
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Required' : null,
              ),

              const SizedBox(height: 16),

              // CATEGORY
              TextFormField(
                controller: _categoryController,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Required' : null,
              ),

              const SizedBox(height: 16),

              // DESCRIPTION
              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Required' : null,
              ),

              const SizedBox(height: 16),

              // LOCATION
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _isLocating ? null : getLocation,
                child: _isLocating
                    ? const CircularProgressIndicator()
                    : const Text('Get your current position'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: (_latitude == null && _longitude == null)
                    ? null
                    : clearLocation,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Remove location'),
              ),

              // VERIFICATION OF LATITUDE / LONGITUDE
              if (_latitude != null && _longitude != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: const [
                      Icon(Icons.check_circle, color: Colors.green),
                      SizedBox(width: 8),
                      Text(
                        "Position detected",
                        style: TextStyle(color: Colors.green),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // PHONE
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 24),

              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),

              const SizedBox(height: 12),

              ElevatedButton(
                onPressed: _isLoading ? null : createRequest,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Create Request'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
