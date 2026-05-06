import 'package:flutter/material.dart';
import '../services/request_service.dart';
import '../models/request_model.dart';
import '../services/location_service.dart';

class RequestEditScreen extends StatefulWidget {
  final RequestModel request;

  const RequestEditScreen({super.key, required this.request});

  @override
  State<RequestEditScreen> createState() => _RequestEditScreenState();
}

class _RequestEditScreenState extends State<RequestEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final RequestService _service = RequestService();

  final _titleController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _phoneController = TextEditingController();

  double? _latitude;
  double? _longitude;

  bool _isLoading = false;
  bool _isLocating = false;
  String? _error;
  String? lastCreatedId;

  @override
  void initState() {
    super.initState();

    _titleController.text = widget.request.title;
    _categoryController.text = widget.request.category;
    _descriptionController.text = widget.request.description;
    _locationController.text = widget.request.location ?? '';
    _phoneController.text = widget.request.phone;
    _latitude = widget.request.latitude;
    _longitude = widget.request.longitude;
  }

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

  /// Update
  Future<void> updateRequest() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      double? latitude = _latitude;
      double? longitude = _longitude;

      if (latitude == null || longitude == null) {
        if (_locationController.text.trim().isEmpty) {
          setState(() => _error = 'Location required');
          return;
        }

        try {
          final loc = await LocationService().getLocationFromAddress(
            _locationController.text.trim(),
          );

          latitude = loc.latitude;
          longitude = loc.longitude;
        } catch (e) {
          setState(() => _error = 'Invalid location');
          return;
        }
      }

      await _service.updateRequest(widget.request.id, {
        'title': _titleController.text.trim(),
        'category': _categoryController.text.trim(),
        'description': _descriptionController.text.trim(),
        'location': _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
        'latitude': latitude,
        'longitude': longitude,
        'phone': _phoneController.text.trim(),
        'status': RequestStatus.active.name,
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Request updated')));

      Navigator.pop(context);
    } catch (e) {
      setState(() {
        _error = 'Failed to update request';
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
      appBar: AppBar(title: const Text('Edit Request')),
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
                  labelText: 'Location (optional)',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 12),

              /// BUTTON FOR POSITION
              ElevatedButton(
                onPressed: _isLocating ? null : getLocation,
                child: _isLocating
                    ? const CircularProgressIndicator()
                    : const Text('Get your current position'),
              ),

              ElevatedButton(
                onPressed: clearLocation,
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
                onPressed: _isLoading ? null : updateRequest,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Update Request'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
