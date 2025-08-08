import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ermis/services/auth_service.dart';

/// Attempts to select the driver's outlet automatically using the API.
/// If not found, prompts the user to pick one.
/// Then sets outlet info in SharedPreferences and activates it in the coordinator.
Future<void> selectAndActivateOutlet(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  final companyId = prefs.getInt('company_id');
  final phone = prefs.getString('phone');
  final w4CompanyCode = prefs.getString('w4_company_code');
  final String apiKey = "1234567890";

  if (companyId == null || (phone == null && w4CompanyCode == null)) {
    print('[selectAndActivateOutlet] Missing company or phone/w4CompanyCode');
    return;
  }

  // Try to fetch last used outlet via API, but catch errors!
  Map<String, dynamic>? outlet;
  try {
    if (phone != null) {
      outlet = await AuthService.fetchLastOutlet(phone: phone);
    }
  } catch (e) {
    print('[selectAndActivateOutlet] Failed to fetch last outlet: $e');
    outlet = null; // Fallback to manual selection
  }

  String? outletName;
  int? outletId;

  if (outlet != null) {
    outletName = outlet['outlet_name'];
    outletId = outlet['outlet_id'] is int
        ? outlet['outlet_id']
        : int.parse(outlet['outlet_id'].toString());
    print('Outlet auto-selected from API: $outletName');
  } else {
    // Fallback: Prompt user to pick one
    final outlets = await AuthService.getOutletsByCompanyId(companyId);
    if (outlets != null && outlets.isNotEmpty) {
      final selectedOutlet = await showOutletSelectDialog(context, outlets);
      if (selectedOutlet != null) {
        outletName = selectedOutlet['name'];
        outletId = selectedOutlet['id'] is int
            ? selectedOutlet['id']
            : int.parse(selectedOutlet['id'].toString());
        print('User selected outlet: $outletName');
      }
    }
  }


  if (outletName != null && outletId != null) {
    await prefs.setString('outlet_name', outletName);
    await prefs.setInt('outlet_id', outletId);

    // Now send selection to coordinator
    final String? mobile = prefs.getString('mobile') ?? phone;
    if (mobile != null && w4CompanyCode != null) {
      final result = await AuthService.setDriverActiveOutlet(
        mobile: mobile,
        w4CompanyCode: w4CompanyCode,
        outletName: outletName,
        apiKey: apiKey,
      );
      print('SetDriverActiveOutlet result: $result');
    }
  } else {
    print('No outlet selected or found.');
  }
}

  Future<Map<String, dynamic>?> showOutletSelectDialog(
    BuildContext context, List<dynamic> outlets) async {
  int? selectedOutletId = outlets[0]['id'];

  return showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Select Outlet'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: outlets.map<Widget>((outlet) {
                return RadioListTile<int>(
                  title: Text(outlet['name']),
                  value: outlet['id'],
                  groupValue: selectedOutletId,
                  onChanged: (value) {
                    setState(() {
                      selectedOutletId = value;
                    });
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final selected = outlets
                    .firstWhere((o) => o['id'] == selectedOutletId);
                Navigator.of(context).pop(selected);
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
    },
  );
}


