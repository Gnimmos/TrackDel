import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ermis/services/auth_service.dart';

Future<void> pickAndActivateOutlet(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  final companyId = prefs.getInt('company_id');
  if (companyId == null) {
    _showDialog(context, 'Error', 'Company not set. Please login again.');
    return;
  }

  final outlets = await AuthService.getOutletsByCompanyId(companyId);
  if (outlets == null || outlets.isEmpty) {
    _showDialog(context, 'Error', 'No outlets found for this company.');
    return;
  }

  final selectedOutlet = await showOutletSelectDialog(context, outlets);
  if (selectedOutlet != null) {
    final outletName = selectedOutlet['name'];
    final outletId = selectedOutlet['id'] is int
        ? selectedOutlet['id']
        : int.parse(selectedOutlet['id'].toString());

    await prefs.setString('outlet_name', outletName);
    await prefs.setInt('outlet_id', outletId);

    // Update coordinator API
    final phone = prefs.getString('phone');
    final w4CompanyCode = prefs.getString('w4_company_code');
    const apiKey = "1234567890";
    final mobile = prefs.getString('mobile') ?? phone;

    if (mobile != null && w4CompanyCode != null) {
      final result = await AuthService.setDriverActiveOutlet(
        mobile: mobile,
        w4CompanyCode: w4CompanyCode,
        outletName: outletName,
        apiKey: apiKey,
      );
      print('SetDriverActiveOutlet result: $result');
    }

    // User feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('You are now active for outlet "$outletName".')),
    );
  }
}

Future<Map<String, dynamic>?> showOutletSelectDialog(
  BuildContext context, List<dynamic> outlets) async {
  final prefs = await SharedPreferences.getInstance();
  final prefOutletId = prefs.getInt('outlet_id');
  final allIds = outlets
      .map((o) => o['id'] is int ? o['id'] : int.tryParse(o['id'].toString()))
      .toList();
  int? selectedOutletId = (prefOutletId != null && allIds.contains(prefOutletId))
      ? prefOutletId
      : allIds.first;

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
                final outletId = outlet['id'] is int
                    ? outlet['id']
                    : int.tryParse(outlet['id'].toString());
                return RadioListTile<int>(
                  title: Text(outlet['name']),
                  value: outletId,
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
                final selected = outlets.firstWhere((o) =>
                    (o['id'] is int
                        ? o['id']
                        : int.tryParse(o['id'].toString())) == selectedOutletId);
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

void _showDialog(BuildContext context, String title, String message) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
      ],
    ),
  );
}
