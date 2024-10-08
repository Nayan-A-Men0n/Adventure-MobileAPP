import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'UserData.dart';
import 'package:provider/provider.dart';

class Screen {
  final String name;
  bool isSelected;

  Screen({required this.name, this.isSelected = false});

  factory Screen.fromJson(Map<String, dynamic> json) {
    return Screen(name: json['screen_name']);
  }
}

class ScreenSelectionPage extends StatefulWidget {
  const ScreenSelectionPage({Key? key}) : super(key: key);

  @override
  _ScreenSelectionPageState createState() => _ScreenSelectionPageState();
}

class _ScreenSelectionPageState extends State<ScreenSelectionPage> {
  List<Screen> screens = [];
  List<String> _locations = [];
  List<String> _businessTypes = [];
  String? _selectedLocation;
  String? _selectedBusinessType;
  Set<String> _selectedScreens = {};
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  DateTime? _selectedDate;
  List<String> _timeSlots = [];
  File? _vidFile;
  bool _isAdUploaded = false;
  String? _userId; 
  int? _adId;

  @override
  void initState() {
    super.initState();
    fetchLocations();
    fetchBusinessTypes();
    _selectedDate = DateTime.now();
    _fetchTimeSlots();
    _userId = Provider.of<UserData>(context, listen: false).userId.toString();
  }

  Future<void> fetchLocations() async {
    final response =
        await http.get(Uri.parse('http://127.0.0.1:5000/locations'));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List;
      setState(() {
        _locations.addAll(data.cast<String>());
      });
    } else {
      print('Failed to fetch locations: ${response.statusCode}');
    }
  }

  Future<void> fetchBusinessTypes() async {
    final response =
        await http.get(Uri.parse('http://127.0.0.1:5000/business_type'));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List;
      setState(() {
        _businessTypes.addAll(data.cast<String>());
      });
    } else {
      print('Failed to fetch business types: ${response.statusCode}');
    }
  }

  Future<void> fetchScreens(
      String? selectedLocation, String? selectedBusinessType) async {
    String url = 'http://127.0.0.1:5000/screens';

    if (selectedLocation != null && selectedLocation.isNotEmpty) {
      url += '?location=$selectedLocation';
    }
    if (selectedBusinessType != null && selectedBusinessType != 'All') {
      if (url.contains('?')) {
        url += '&';
      } else {
        url += '?';
      }
      url += 'business_type=$selectedBusinessType';
    }

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final screenNames = data['screen_names'] as List<dynamic>;

      setState(() {
        screens = screenNames
            .map((name) => Screen.fromJson({'screen_name': name}))
            .toList();
      });
    } else {
      print('Failed to fetch screen names: ${response.statusCode}');
    }
  }

  Future<void> _pickStartTime(String screenName) async {
    final initialTime = _startTime ?? TimeOfDay.now();
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (pickedTime != null) {
      final pickedDateTime =
          DateTime(1, 1, 1, pickedTime.hour, pickedTime.minute);
      // Check for duplicate start time
      final duplicateStartTime = _timeSlots.any((slot) {
        final parts = slot.split('-');
        final slotStartTimeParts = parts[0].trim().split(':');
        final slotEndTimeParts = parts[1].trim().split(':');
        final slotStartTime = DateTime(1, 1, 1,
            int.parse(slotStartTimeParts[0]), int.parse(slotStartTimeParts[1]));
        final slotEndTime = DateTime(1, 1, 1, int.parse(slotEndTimeParts[0]),
            int.parse(slotEndTimeParts[1]));
        // Check if the picked time falls within any existing slot
        return pickedDateTime.isAfter(slotStartTime) &&
            pickedDateTime.isBefore(slotEndTime);
      });

      // Check for overlap with unavailable time slots
      final unavailableStartTimeCollide = _timeSlots.any((slot) {
        final parts = slot.split('-');
        final slotStartTimeParts = parts[0].trim().split(':');
        final slotStartTime = DateTime(1, 1, 1,
            int.parse(slotStartTimeParts[0]), int.parse(slotStartTimeParts[1]));
        return pickedDateTime == slotStartTime;
      });

      if (duplicateStartTime || unavailableStartTimeCollide) {
        // Show error message for duplicate start time or overlap with unavailable slots
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Start time conflicts with existing booked or unavailable slots.'),
          ),
        );
      } else {
        setState(() {
          _startTime = pickedTime;
        });
      }
    }
  }

  Future<void> _pickEndTime(String screenName) async {
    if (_startTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a start time first'),
        ),
      );
      return;
    }

    final startTimeDateTime =
        DateTime(1, 1, 1, _startTime!.hour, _startTime!.minute);
    final endTimeDateTime = startTimeDateTime.add(const Duration(minutes: 15));

    final endTime =
        TimeOfDay(hour: endTimeDateTime.hour, minute: endTimeDateTime.minute);

    // Check if the end time falls within any existing slot
    final endTimeOverlap = _timeSlots.any((slot) {
      final parts = slot.split('-');
      final slotStartTimeParts = parts[0].trim().split(':');
      final slotEndTimeParts = parts[1].trim().split(':');
      final slotStartTime = DateTime(1, 1, 1, int.parse(slotStartTimeParts[0]),
          int.parse(slotStartTimeParts[1]));
      final slotEndTime = DateTime(1, 1, 1, int.parse(slotEndTimeParts[0]),
          int.parse(slotEndTimeParts[1]));
      return endTimeDateTime.isAfter(slotStartTime) &&
          endTimeDateTime.isBefore(slotEndTime);
    });

    if (endTimeOverlap) {
      // Show error message for end time overlap
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End time conflicts with existing booked slots.'),
        ),
      );
    } else {
      // Pass selected screen name, location, and business type to calculate cost
      final selectedLocation = _selectedLocation;
      final selectedBusinessType = _selectedBusinessType;
      if (selectedLocation != null && selectedBusinessType != null) {
        final cost = await calculateCost(
          startTimeDateTime,
          endTimeDateTime,
          selectedLocation,
          selectedBusinessType,
          [_selectedScreens.toString()], // Pass selected screen names as a list
        );
        final costText =
            cost != null ? 'You have to pay a price of \$$cost' : '';

        // Show cost below the selected times
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(costText),
          ),
        );
      }

      setState(() {
        _endTime = endTime;
      });
    }
  }

  Future<void> _pickDate(BuildContext context) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(DateTime.now().year + 5),
    );

    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate;
        // Fetch time slots when date is selected
        _fetchTimeSlots();
      });
    }
  }

  Future<double?> calculateCost(
    DateTime startTime,
    DateTime endTime,
    String selectedLocation,
    String selectedBusinessType,
    List<String> selectedScreenNames,
  ) async {
    try {
      final url = Uri.parse('http://127.0.0.1:5000/calculate_cost');
      final response = await http.post(
        url,
        body: jsonEncode({
          'start_time': startTime.toIso8601String(),
          'end_time': endTime.toIso8601String(),
          'location': selectedLocation,
          'business_type': selectedBusinessType,
          'screen_names': selectedScreenNames.map((name) => '{$name}').toList(),
        }),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return double.parse(data['total_cost']);
      } else {
        print('Failed to calculate cost: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error calculating cost: $e');
      return null;
    }
  }

  void _filterScreens(String? selectedLocation, String? selectedBusinessType) {
    if (selectedLocation == null || selectedBusinessType == null) {
      return;
    }

    fetchScreens(selectedLocation, selectedBusinessType);
  }

  Future<void> _fetchTimeSlots() async {
    if (_selectedLocation == null ||
        _selectedBusinessType == null ||
        _selectedScreens.isEmpty ||
        _selectedDate == null) {
      return;
    }

    final selectedScreensData =
        _selectedScreens.toList(); 

    final requestBody = {
      'location': _selectedLocation!,
      'business_type': _selectedBusinessType!,
      'screen_names':
          selectedScreensData,
      'date': _selectedDate!.toIso8601String(),
    };

    try {
      final url = Uri.parse('http://127.0.0.1:5000/booked_slots');
      final response = await http.post(
        url,
        body: jsonEncode(requestBody),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final timeSlots = data['booked_slots'] as List<dynamic>;
        setState(() {
          _timeSlots = timeSlots.map((slot) => slot.toString()).toList();
        });
      } else {
        print('Failed to fetch time slots: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching time slots: $e');
    }
  }

  Future<void> adsschedule() async {
    final selectedScreenNames = _selectedScreens.toList();
    if (_selectedScreens.isEmpty || _startTime == null || _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select screens, start time, and end time'),
        ),
      );
      return;
    }

    final selectedData = selectedScreenNames
        .map((screenName) => {
              'screen_name': screenName,
            })
        .toList();

    final selectedLocation = _selectedLocation;
    if (selectedLocation != null) {
      selectedData.add({'location': selectedLocation});
    }

    final selectedBusinessType = _selectedBusinessType;
    if (selectedBusinessType != null) {
      selectedData.add({'business_type': selectedBusinessType});
    }

    final url = Uri.parse('http://127.0.0.1:5000/ad_schedule');

    final body = jsonEncode({
      'screens': selectedData, // Use the prepared "selectedData" list
      'start_time': _startTime!.format(context),
      'end_time': _endTime!.format(context),
      'date': _selectedDate!.toIso8601String(),
      'ad_id': _adId, // Pass the ad_id to the backend
    });

    final response = await http.post(
      url,
      body: body,
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ad schedule created successfully!'),
        ),
      );
      setState(() {
        _selectedScreens.clear();
        _startTime = null;
        _endTime = null;
      });
    } else {
      print('Failed to schedule ads: ${response.statusCode}');
    }
  }

  String extractFileName(String filePath) {
    List<String> pathParts = filePath.split(Platform.pathSeparator);
    return pathParts.last;
  }

  Future<void> uploadAd(int userId) async {
    if (_vidFile == null) return;

    final Uri url = Uri.parse('http://127.0.0.1:5000/upload');
    var request = http.MultipartRequest('POST', url);

    // Extract file name from the file path
    String fileName = extractFileName(_vidFile!.path);

    // Send the file name instead of the file path
    request.fields['vid_file_name'] = fileName; // Only the file name is sent
    request.fields['advertiser_id'] = userId.toString();

    final response = await request.send();

    if (response.statusCode == 200) {
      try {
        
        final String responseString = await response.stream.bytesToString();
        final dynamic responseData = jsonDecode(responseString);

        if (responseData is Map<String, dynamic> &&
            responseData.containsKey('ad_id')) {
          final int adId = responseData['ad_id'] as int;

          
          setState(() {
            _isAdUploaded = true; // Update ad upload status
            _vidFile = null; // Clear image selection after successful upload
            _adId = adId; // Store ad_id in a variable
          });
          print(_adId);

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File uploaded successfully!')),
          );
          return;
        } else {
          throw Exception('Invalid response format');
        }
      } catch (e) {
        print('Error parsing response: $e');
        
      }
    } else {
      print('Error: ${response.reasonPhrase}');
      
    }
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform
        .pickFiles(allowMultiple: false, type: FileType.any);
    if (result != null) {
      setState(() {
        _vidFile = File(result.files.single.path!);
      });
    } else {
     
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Screen Selection'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: _selectedLocation,
              hint: const Text('Select Location'),
              items: _locations
                  .map((location) => DropdownMenuItem<String>(
                        value: location,
                        child: Text(location),
                      ))
                  .toList(),
              onChanged: (location) =>
                  setState(() => _selectedLocation = location),
            ),
            const SizedBox(height: 16.0),
            DropdownButtonFormField<String>(
              value: _selectedBusinessType,
              hint: const Text('Select Business Type'),
              items: _businessTypes
                  .map((businessType) => DropdownMenuItem<String>(
                        value: businessType,
                        child: Text(businessType),
                      ))
                  .toList(),
              onChanged: (businessType) =>
                  setState(() => _selectedBusinessType = businessType),
            ),
            const SizedBox(height: 16.0),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _filterScreens(
                        _selectedLocation, _selectedBusinessType),
                    icon: const Icon(Icons.filter_list),
                    label: const Text('Filter Screens'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(150.0, 50.0), 
                      backgroundColor: Colors.blue,
                    ),
                  ),
                ),
                const SizedBox(width: 16.0), 
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickDate(context),
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('Select Date'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(150.0, 50.0), 
                      backgroundColor: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16.0),
            if (screens.isNotEmpty)
              const Text(
                'Selected Screens:',
                style: TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 8.0),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: screens.length,
                itemBuilder: (context, index) {
                  final screen = screens[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 200,
                            child: CheckboxListTile(
                              title: Text(screen.name),
                              value: screen.isSelected,
                              onChanged: (newValue) => setState(() {
                                screen.isSelected = newValue ?? false;
                                if (newValue!) {
                                  _selectedScreens.add(screen.name);
                                } else {
                                  _selectedScreens.remove(screen.name);
                                }
                              }),
                            ),
                          ),
                          const SizedBox(
                              width:
                                  16.0), 
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Unavailable Time Slots',
                                  style: TextStyle(
                                    fontSize: 16.0,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (_timeSlots.isNotEmpty) ...[
                                  ..._timeSlots.map((timeSlot) {
                                    return Text(
                                      timeSlot,
                                      style: const TextStyle(
                                          fontSize:
                                              16.0), 
                                    );
                                  }),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => _pickStartTime(screen.name),
                            child: Text(_startTime?.format(context) ??
                                'Select Start Time'),
                          ),
                          const SizedBox(width: 4.0),
                          Text('- 15 min'),
                          const SizedBox(width: 4.0),
                          TextButton(
                            onPressed: () => _pickEndTime(screen.name),
                            child: Text(
                                _endTime?.format(context) ?? 'Select End Time'),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16.0),
            ElevatedButton(
              onPressed: () async {
                await _pickImage();
                if (_userId != null) {
                  uploadAd(int.parse(_userId!));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('User ID not available.'),
                    ),
                  );
                }
              },
              child: Text('Select File'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50.0),
                backgroundColor: Colors.orange,
              ),
            ),
            const SizedBox(height: 8.0), 
            ElevatedButton(
              onPressed: () {
                adsschedule();
              },
              child: Text('Schedule Ads'),
              style: ElevatedButton.styleFrom(
                  // Set color to grey when button is disabled
                  foregroundColor: _isAdUploaded ? null : Colors.grey,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  
}
