  import 'package:flutter/material.dart';
  import 'package:ermis/services/auth_service.dart';
  import 'package:shared_preferences/shared_preferences.dart';
  import 'package:url_launcher/url_launcher.dart';
  import 'package:ermis/services/delivery_service.dart';
  import 'package:package_info_plus/package_info_plus.dart';
  import 'package:ermis/helpers/select_outlet_helper.dart';

  class LoginScreen extends StatefulWidget {
    const LoginScreen({super.key});

    @override
    State<LoginScreen> createState() => _LoginScreenState();
  }

  class _LoginScreenState extends State<LoginScreen> {
    final _phoneController = TextEditingController();
    final _passwordController = TextEditingController();

    bool _isLoading = false;
    String? _errorMessage;
    String? _version;

    @override
    void initState() {
      super.initState();
        _getAppVersion();
    }
    void _getAppVersion() async {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _version = 'v${packageInfo.version}';
      });
    }
    Future<void> _checkForSavedSession() async {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getInt('session_id');
      final driverId = prefs.getInt('driver_id');

      print('[LoginScreen] Checking for saved session: sessionId=$sessionId, driverId=$driverId');

      if (sessionId != null && driverId != null) {
        // Check for active orders
        final hasOrders = await DeliveryService.hasPendingDeliveries(driverId);
        print('[LoginScreen] Has pending deliveries: $hasOrders');

        // You may want to check sessionActive status from backend if needed
        // For now, assume saved session is active if present, or just rely on hasOrders

        if (hasOrders) {
          // AUTO-RESUME if there are active orders
          print('[LoginScreen] Auto-resume session (pending deliveries)');
          setState(() => _isLoading = true);
          final resumed = await AuthService.resumeSession(sessionId);
          setState(() => _isLoading = false);

          if (resumed != null && resumed['success'] == true) {
            if (resumed['session_id'] != null) await prefs.setInt('session_id', resumed['session_id']);
            if (resumed['driver_id'] != null) await prefs.setInt('driver_id', resumed['driver_id']);
            if (resumed['token'] != null) await prefs.setString('token', resumed['token']);
            if (resumed['company_id'] != null) await prefs.setInt('company_id', resumed['company_id']);
            if (resumed['w4_company_code'] != null) await prefs.setString('w4_company_code', resumed['w4_company_code'].toString());

            print('[LoginScreen] Session resumed automatically (pending deliveries)');
            if (!mounted) return;
            Navigator.pushReplacementNamed(context, '/pending');
            return;
          } else {
            await prefs.remove('session_id');
            await prefs.remove('driver_id');
            await prefs.remove('token');
            await prefs.remove('company_id');
            await prefs.remove('w4_company_code');

            print('[LoginScreen] Failed to resume session automatically.');
          }
        } else {
          // Otherwise, prompt user
          final shouldContinue = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('Continue previous session?'),
              content: const Text('You have an active session. Do you want to continue it?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Logout'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Continue'),
                ),
              ],
            ),
          );

          print('[LoginScreen] User selected to continue session: $shouldContinue');

          if (shouldContinue == true) {
            setState(() => _isLoading = true);
            final resumed = await AuthService.resumeSession(sessionId);
            setState(() => _isLoading = false);

            if (resumed != null && resumed['success'] == true) {
              if (resumed['session_id'] != null) await prefs.setInt('session_id', resumed['session_id']);
              if (resumed['driver_id'] != null) await prefs.setInt('driver_id', resumed['driver_id']);
              if (resumed['token'] != null) await prefs.setString('token', resumed['token']);
              if (resumed['company_id'] != null) await prefs.setInt('company_id', resumed['company_id']);
              if (resumed['w4_company_code'] != null) await prefs.setString('w4_company_code', resumed['w4_company_code'].toString());

              print('[LoginScreen] Session resumed by user choice.');
              if (!mounted) return;
              Navigator.pushReplacementNamed(context, '/pending');
              return;
            } else {
              await prefs.remove('session_id');
              await prefs.remove('driver_id');
              await prefs.remove('token');
              await prefs.remove('company_id');
              await prefs.remove('w4_company_code');

              print('[LoginScreen] Failed to resume session (user chose yes).');
            }
          } else {
            // User chose to logout
            await prefs.remove('session_id');
            await prefs.remove('driver_id');
            await prefs.remove('token');
            await prefs.remove('company_id');
            await prefs.remove('w4_company_code');

            print('[LoginScreen] User chose to logout.');
          }
        }
      }
    }

    void _handleLogin() async {
      final phone = _phoneController.text.trim();
      final password = _passwordController.text;
      final apiKey = "1234567890";

      if (phone.isEmpty || password.isEmpty) {
        setState(() => _errorMessage = "Phone and password are required.");
        return;
      }

      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final result = await AuthService.login(phone, password);

      if (result['success']) {

        print('[LoginScreen] Backend login successful. Now calling QWD Coordinator login...');

        // QWD COORDINATOR LOGIN (after ba  ckend)
        final qwdResult = await AuthService.loginCoordinatorQWD(phone, password, apiKey);
        print('[LoginScreen] QWD login result: $qwdResult');

        if (!qwdResult['success']) {
          print('[LoginScreen] QWD Coordinator login failed: ${qwdResult['message']}');
          setState(() {
            _errorMessage = qwdResult['message'] ?? 'QWD Coordinator login failed';
            _isLoading = false;
          });
          return;
        } else {
          print('[LoginScreen] QWD Coordinator login successful!');
        }
      

        final prefs = await SharedPreferences.getInstance();
        if (result['session_id'] != null) await prefs.setInt('session_id', result['session_id']);
        if (result['driver_id'] != null) await prefs.setInt('driver_id', result['driver_id']);
        if (result['token'] != null) await prefs.setString('token', result['token']);
        if (result['company_id'] != null) await prefs.setInt('company_id', result['company_id'].toInt());
        if (result['w4_company_code'] != null) await prefs.setString('w4_company_code', result['w4_company_code'].toString());
        if (phone.isNotEmpty) await prefs.setString('phone', phone); 
        
        await selectAndActivateOutlet(context);

        // Now check for outlet
        final outletId = prefs.getInt('outlet_id');
        if (outletId == null) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'You must select an outlet to continue.';
          });
          return;
        }

        final canResume = result['can_resume'] ?? false;
        final sessionActive = result['session_active'] ?? false;

        print('[LoginScreen] Login: canResume=$canResume, sessionActive=$sessionActive');

        bool hasOrders = false;
        if (result['driver_id'] != null) {
          hasOrders = await DeliveryService.hasPendingDeliveries(result['driver_id']);
          print('[LoginScreen] Login: Has pending deliveries: $hasOrders');
        }

        if (canResume && (sessionActive == true || hasOrders)) {
          // AUTO-RESUME if session is active or has orders
          print('[LoginScreen] Auto-resume after login');
          if (sessionActive == true) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Session continued successfully")),
            );
            Navigator.pushReplacementNamed(context, '/pending');
            return;
          } else {
            setState(() => _isLoading = true);
            final resumed = await AuthService.resumeSession(result['session_id']);
            setState(() => _isLoading = false);

            if (resumed != null && resumed['success'] == true) {
              if (phone != null) await prefs.setString('phone', phone);
              if (resumed['session_id'] != null) await prefs.setInt('session_id', resumed['session_id']);
              if (resumed['driver_id'] != null) await prefs.setInt('driver_id', resumed['driver_id']);
              if (resumed['token'] != null) await prefs.setString('token', resumed['token']);
              if (resumed['company_id'] != null) await prefs.setInt('company_id', resumed['company_id']);
              if (resumed['w4_company_code'] != null) await prefs.setString('w4_company_code', resumed['w4_company_code'].toString());


              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Session resumed automatically (pending deliveries)")),
              );
              if (!mounted) return;
              Navigator.pushReplacementNamed(context, '/pending');
              return;
            } else {
              await prefs.remove('session_id');
              await prefs.remove('driver_id');
              await prefs.remove('token');
              await prefs.remove('company_id');
              await prefs.remove('w4_company_code');

              setState(() => _errorMessage = "Failed to resume session.");
              print('[LoginScreen] Failed to resume session (auto).');
              return;
            }
          }
        }

        if (canResume) {
          // Prompt user if not auto-resumed
          final shouldResume = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('Continue previous session?'),
              content: const Text('A previous session exists. Do you want to continue it?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('No'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Yes'),
                ),
              ],
            ),
          );
          print('[LoginScreen] User selected to continue session: $shouldResume');
          if (shouldResume == true) {
            setState(() => _isLoading = true);
            final resumed = await AuthService.resumeSession(result['session_id']);
            setState(() => _isLoading = false);

            if (resumed != null && resumed['success'] == true) {
              if (resumed['session_id'] != null) await prefs.setInt('session_id', resumed['session_id']);
              if (resumed['driver_id'] != null) await prefs.setInt('driver_id', resumed['driver_id']);
              if (resumed['token'] != null) await prefs.setString('token', resumed['token']);
              if (resumed['company_id'] != null) await prefs.setInt('company_id', resumed['company_id']);
              if (resumed['w4_company_code'] != null) await prefs.setString('w4_company_code', resumed['w4_company_code'].toString());

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Session resumed successfully")),
              );
              if (!mounted) return;
              Navigator.pushReplacementNamed(context, '/pending');
              return;
            } else {
              await prefs.remove('session_id');
              await prefs.remove('driver_id');
              await prefs.remove('token');
              await prefs.remove('company_id');
              await prefs.remove('w4_company_code');

              setState(() => _errorMessage = "Failed to resume session.");
              print('[LoginScreen] Failed to resume session (user chose yes).');
              return;
            }
          }
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Login successful")),
        );
        Navigator.pushReplacementNamed(context, '/pending');
      } else {
        setState(() => _errorMessage = result['message'] ?? 'Login failed');
      }

      setState(() => _isLoading = false);
      
    }

    void _launchPrivacyPolicy() async {
      final Uri url = Uri.parse('http://4.184.202.172:3212/privacypolicy');
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        print('❌ Could not launch Privacy Policy');
      }
    }


    @override
    Widget build(BuildContext context) {
      return Scaffold(
        appBar: AppBar(title: const Text('Driver Login')),
        body: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                  ),
                  const SizedBox(height: 24),
                  if (_errorMessage != null)
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Login'),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 12,
              right: 16,
              child: GestureDetector(
                onTap: _launchPrivacyPolicy,
                child: Text(
                  'Privacy Policy',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 16,
              child: Text(
                _version ?? '1.0.3',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ],
        ),
      );
    }
  }
