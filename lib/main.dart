import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'dart:io';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('customers');
    if (data != null) {
      final List decoded = jsonDecode(data);
      final today = DateTime.now();

      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initSettings =
          InitializationSettings(android: androidSettings);
      await flutterLocalNotificationsPlugin.initialize(initSettings);

      for (var item in decoded) {
        final renewal = DateTime.parse(item['renewalDate']);
        if (renewal.year == today.year &&
            renewal.month == today.month &&
            renewal.day == today.day) {
          await _showNotification(item['name'], item['phone']);
        }
      }
    }
    return Future.value(true);
  });
}

Future<void> _showNotification(String name, String phone) async {
  final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'renewal_channel',
    'Renewal Alerts',
    channelDescription: 'Daily gas cylinder renewal alerts',
    importance: Importance.high,
    priority: Priority.high,
    fullScreenIntent: true,
    styleInformation: BigTextStyleInformation(
      '$name — $phone needs a gas cylinder renewal today!',
      summaryText: 'Tap to open app',
    ),
  );
  final NotificationDetails details =
      NotificationDetails(android: androidDetails);
  await flutterLocalNotificationsPlugin.show(
    name.hashCode,
    '🔔 Renewal Due Today: $name',
    '$name — $phone needs a cylinder renewal!',
    details,
    payload: 'renewal',
  );
}

Future<void> initNotifications() async {
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  final InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);
  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {},
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  await Workmanager().registerPeriodicTask(
    'renewal-check',
    'checkRenewals',
    frequency: const Duration(hours: 24),
    initialDelay: const Duration(seconds: 10),
  );
  runApp(const GasCylinderApp());
}

// ─── App Colors ───────────────────────────────────────────────────────────────
class AppColors {
  static const background    = Color(0xFFEFF6EE);
  static const primary       = Color(0xFF2E7D32);
  static const cardGreen     = Color(0xFFD6EDD6);
  static const cardGreenDark = Color(0xFF7EB97E);
  static const navy          = Color(0xFF1A237E);
  static const orange        = Color(0xFFF57C00);
  static const white         = Colors.white;
  static const textDark      = Color(0xFF1B1B1B);
  static const textGrey      = Color(0xFF7A7A7A);
}

class GasCylinderApp extends StatelessWidget {
  const GasCylinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Home Care Service',
      debugShowCheckedModeBanner: false,
      scrollBehavior:
          const MaterialScrollBehavior().copyWith(overscroll: false),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: AppColors.background,
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const LicenseGate(),
    );
  }
}

// ─── LICENSE GATE ─────────────────────────────────────────────────────────────

class LicenseGate extends StatefulWidget {
  const LicenseGate({super.key});

  @override
  State<LicenseGate> createState() => _LicenseGateState();
}

class _LicenseGateState extends State<LicenseGate> {
  static const String _scriptUrl =
      'Script_url_here'; // TODO: Replace with your actual script URL

  bool _checking = true;
  bool _activated = false;

  @override
  void initState() {
    super.initState();
    _checkActivation();
  }

  Future<void> _checkActivation() async {
    final prefs = await SharedPreferences.getInstance();
    final activated = prefs.getBool('license_activated') ?? false;
    setState(() {
      _activated = activated;
      _checking = false;
    });
  }

  void _onActivated() {
    setState(() => _activated = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFF2E7D32),
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }
    if (_activated) return const HomeScreen();
    return ActivationScreen(
      scriptUrl: _scriptUrl,
      onActivated: _onActivated,
    );
  }
}

// ─── ACTIVATION SCREEN ────────────────────────────────────────────────────────

class ActivationScreen extends StatefulWidget {
  final String scriptUrl;
  final VoidCallback onActivated;

  const ActivationScreen({
    super.key,
    required this.scriptUrl,
    required this.onActivated,
  });

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _keyController = TextEditingController();
  bool _loading = false;
  String? _errorMessage;

  Future<void> _activate() async {
    final key = _keyController.text.trim().toUpperCase();
    if (key.isEmpty) {
      setState(() => _errorMessage = 'Please enter your license key');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final url =
          '${widget.scriptUrl}?action=validate&key=${Uri.encodeComponent(key)}';

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);

      final request = await client.getUrl(Uri.parse(url));
      request.followRedirects = true;
      request.maxRedirects = 10;
      final response = await request.close();

      final responseBody = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode == 200) {
        final body = jsonDecode(responseBody);
        if (body['valid'] == true) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('license_activated', true);
          await prefs.setString('license_key', key);
          await prefs.setString(
              'license_business', body['business'] ?? 'Your Business');
          widget.onActivated();
        } else {
          setState(() => _errorMessage =
              body['message'] ?? 'Invalid key. Please contact support.');
        }
      } else {
        setState(() => _errorMessage =
            'Server error (${response.statusCode}). Please try again.');
      }
    } on SocketException {
      setState(() =>
          _errorMessage = 'No internet connection. Please connect and try again.');
    } catch (e) {
      setState(() => _errorMessage = 'Could not verify key: $e');
    }

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 48),
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.local_fire_department,
                    size: 52, color: Colors.white),
              ),
              const SizedBox(height: 24),
              const Text(
                'Home Care Service',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Customer Management App',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
              const SizedBox(height: 48),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Activate Your License',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Enter the license key provided to you.',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _keyController,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(
                          letterSpacing: 3,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                      decoration: InputDecoration(
                        hintText: 'XXXX-XXXX-XXXX',
                        hintStyle: TextStyle(
                            color: Colors.grey[400],
                            letterSpacing: 2,
                            fontWeight: FontWeight.normal,
                            fontSize: 15),
                        prefixIcon: const Icon(Icons.vpn_key_outlined,
                            color: AppColors.primary),
                        filled: true,
                        fillColor: const Color(0xFFF5F5F5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        errorText: _errorMessage,
                      ),
                      onSubmitted: (_) => _activate(),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _activate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Activate',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Need a license key? Contact us on WhatsApp (7019348778)',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.7), fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Developed by Sikandar Ansari',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.4), fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Customer Model ───────────────────────────────────────────────────────────

class Customer {
  String name;
  String consumerNumber;
  String address;
  String phone;
  DateTime purchaseDate;
  DateTime renewalDate;
  double due;

  Customer({
    required this.name,
    required this.consumerNumber,
    required this.address,
    required this.phone,
    required this.purchaseDate,
    required this.renewalDate,
    this.due = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'consumerNumber': consumerNumber,
        'address': address,
        'phone': phone,
        'purchaseDate': purchaseDate.toIso8601String(),
        'renewalDate': renewalDate.toIso8601String(),
        'due': due,
      };

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        name: json['name'],
        consumerNumber: json['consumerNumber'] ?? json['consignment'] ?? '',
        address: json['address'],
        phone: json['phone'],
        purchaseDate: DateTime.parse(json['purchaseDate']),
        renewalDate: DateTime.parse(json['renewalDate']),
        due: (json['due'] ?? 0).toDouble(),
      );
}

DateTime _parseDate(String raw) {
  final parts = raw.trim().split('/');
  return DateTime(
    int.parse(parts[2]),
    int.parse(parts[1]),
    int.parse(parts[0]),
  );
}

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

// ─── Filter Model ─────────────────────────────────────────────────────────────

enum DuesFilter { all, hasDues, noDues }

class CustomerFilter {
  DuesFilter duesFilter;
  DateTime? renewalFrom;
  DateTime? renewalTo;

  CustomerFilter({
    this.duesFilter = DuesFilter.all,
    this.renewalFrom,
    this.renewalTo,
  });

  bool get isActive =>
      duesFilter != DuesFilter.all ||
      renewalFrom != null ||
      renewalTo != null;

  CustomerFilter copyWith({
    DuesFilter? duesFilter,
    DateTime? renewalFrom,
    DateTime? renewalTo,
    bool clearRenewalFrom = false,
    bool clearRenewalTo = false,
  }) {
    return CustomerFilter(
      duesFilter: duesFilter ?? this.duesFilter,
      renewalFrom: clearRenewalFrom ? null : (renewalFrom ?? this.renewalFrom),
      renewalTo: clearRenewalTo ? null : (renewalTo ?? this.renewalTo),
    );
  }
}

// ─── Home Screen ──────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Customer> _customers = [];
  bool _loading = true;
  String _searchQuery = '';
  CustomerFilter _filter = CustomerFilter();

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('customers');
    if (data != null) {
      final List decoded = jsonDecode(data);
      setState(() {
        _customers = decoded.map((e) => Customer.fromJson(e)).toList();
      });
    }
    setState(() => _loading = false);
  }

  Future<void> _saveCustomers() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_customers.map((c) => c.toJson()).toList());
    await prefs.setString('customers', data);
  }

  bool _isDueToday(Customer c) {
    final today = DateTime.now();
    return c.renewalDate.year == today.year &&
        c.renewalDate.month == today.month &&
        c.renewalDate.day == today.day;
  }

  List<Customer> get _todayRenewals =>
      _customers.where((c) => _isDueToday(c)).toList();

  List<Customer> get _upcomingRenewals {
    final today = DateTime.now();
    final soon = today.add(const Duration(days: 7));
    return _customers.where((c) {
      return c.renewalDate.isAfter(today) && c.renewalDate.isBefore(soon);
    }).toList();
  }

  double get _totalDue => _customers.fold(0.0, (sum, c) => sum + c.due);

  List<Customer> get _filteredCustomers {
    List<Customer> list = _customers;
    if (_searchQuery.isNotEmpty) {
      list = list.where((c) {
        return c.name.toLowerCase().contains(_searchQuery) ||
            c.phone.toLowerCase().contains(_searchQuery) ||
            c.consumerNumber.toLowerCase().contains(_searchQuery);
      }).toList();
    }
    if (_filter.duesFilter == DuesFilter.hasDues) {
      list = list.where((c) => c.due > 0).toList();
    } else if (_filter.duesFilter == DuesFilter.noDues) {
      list = list.where((c) => c.due == 0).toList();
    }
    if (_filter.renewalFrom != null) {
      list = list
          .where((c) => !c.renewalDate.isBefore(_filter.renewalFrom!))
          .toList();
    }
    if (_filter.renewalTo != null) {
      final to = _filter.renewalTo!.add(const Duration(days: 1));
      list = list.where((c) => c.renewalDate.isBefore(to)).toList();
    }
    return list;
  }

  void _addCustomer(Customer customer) {
    setState(() => _customers.add(customer));
    _saveCustomers();
  }

  void _editCustomer(int index, Customer updated) {
    setState(() => _customers[index] = updated);
    _saveCustomers();
  }

  void _deleteCustomer(int index) {
    setState(() => _customers.removeAt(index));
    _saveCustomers();
  }

  // ─── IMPORT CSV ────────────────────────────────────────────────────────────

  Future<void> _importCSV() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (result == null) return;
      final file = File(result.files.single.path!);
      final contents = await file.readAsString();
      final rows = contents
          .trim()
          .split('\n')
          .map((line) => line.split(','))
          .toList();
      if (rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('CSV file is empty!')),
          );
        }
        return;
      }
      final startIndex =
          rows[0][0].toString().toLowerCase().contains('name') ? 1 : 0;
      int imported = 0;
      int failed = 0;
      for (int i = startIndex; i < rows.length; i++) {
        try {
          final row = rows[i];
          if (row.length < 6) continue;
          final customer = Customer(
            name: row[0].toString().trim(),
            consumerNumber: row[1].toString().trim(),
            address: row[2].toString().trim(),
            phone: row[3].toString().trim(),
            purchaseDate: _parseDate(row[4].toString().trim()),
            renewalDate: _parseDate(row[5].toString().trim()),
            due: row.length > 6
                ? double.tryParse(row[6].toString().trim()) ?? 0.0
                : 0.0,
          );
          _customers.add(customer);
          imported++;
        } catch (e) {
          failed++;
        }
      }
      await _saveCustomers();
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(failed == 0
                ? '$imported customers imported successfully!'
                : '$imported imported, $failed rows failed'),
            backgroundColor:
                failed == 0 ? const Color(0xFF2E7D32) : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reading file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─── EXPORT CSV ────────────────────────────────────────────────────────────

  Future<void> _exportCSV() async {
    if (_customers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No customers to export!')),
        );
      }
      return;
    }

    try {
      final buffer = StringBuffer();
      buffer.writeln('name,consumer_number,address,phone,purchase_date,renewal_date,due');
      for (final c in _customers) {
        String escape(String s) => '"${s.replaceAll('"', '""')}"';
        buffer.writeln(
          '${escape(c.name)},'
          '${escape(c.consumerNumber)},'
          '${escape(c.address)},'
          '${escape(c.phone)},'
          '${_formatDate(c.purchaseDate)},'
          '${_formatDate(c.renewalDate)},'
          '${c.due.toStringAsFixed(2)}',
        );
      }

      Directory? dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Download');
        if (!await dir.exists()) {
          dir = await getExternalStorageDirectory();
        }
      } else {
        dir = await getApplicationDocumentsDirectory();
      }

      final now = DateTime.now();
      final fileName =
          'customers_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.csv';

      final file = File('${dir!.path}/$fileName');
      await file.writeAsString(buffer.toString());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_customers.length} customers exported!\nSaved to Downloads/$fileName',
            ),
            backgroundColor: AppColors.primary,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _openFilterSheet() async {
    final result = await showModalBottomSheet<CustomerFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FilterSheet(current: _filter),
    );
    if (result != null) setState(() => _filter = result);
  }

  @override
  Widget build(BuildContext context) {
    final todayList = _todayRenewals;
    final upcomingList = _upcomingRenewals;
    final filtered = _filteredCustomers;

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: AppDrawer(
        onImportCSV: () {
          Navigator.pop(context);
          _importCSV();
        },
        onExportCSV: () {
          Navigator.pop(context);
          _exportCSV();
        },
      ),
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.primary),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Home Care Service',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            Text(
              '${_customers.length} customers total',
              style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Search + Filter ──
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                onChanged: (value) => setState(
                                    () => _searchQuery = value.toLowerCase()),
                                decoration: InputDecoration(
                                  hintText: 'Search by name, phone, consumer no.',
                                  hintStyle: const TextStyle(
                                      color: AppColors.textGrey, fontSize: 14),
                                  prefixIcon: const Icon(Icons.search,
                                      color: AppColors.primary),
                                  filled: true,
                                  fillColor: AppColors.cardGreen,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 0),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(30),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(30),
                                    borderSide: BorderSide(
                                        color: AppColors.primary.withOpacity(0.25),
                                        width: 1),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(30),
                                    borderSide: const BorderSide(
                                        color: AppColors.primary, width: 1.5),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: _openFilterSheet,
                              child: Container(
                                height: 48,
                                width: 48,
                                decoration: BoxDecoration(
                                  color: _filter.isActive
                                      ? AppColors.primary
                                      : AppColors.cardGreen,
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(
                                    color: AppColors.primary.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Icon(Icons.tune,
                                        color: _filter.isActive
                                            ? Colors.white
                                            : AppColors.primary),
                                    if (_filter.isActive)
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: Colors.orange,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),

                        if (_filter.isActive) ...[
                          const SizedBox(height: 10),
                          _ActiveFilterChips(
                            filter: _filter,
                            onClear: () =>
                                setState(() => _filter = CustomerFilter()),
                            onRemoveDues: () => setState(() => _filter =
                                _filter.copyWith(duesFilter: DuesFilter.all)),
                            onRemoveFrom: () => setState(() => _filter =
                                _filter.copyWith(clearRenewalFrom: true)),
                            onRemoveTo: () => setState(() => _filter =
                                _filter.copyWith(clearRenewalTo: true)),
                          ),
                        ],

                        const SizedBox(height: 16),

                        // ── Stat Cards ──
                        Row(
                          children: [
                            _StatCard(
                              label: "Today's Renewals",
                              count: todayList.length,
                              icon: Icons.calendar_month_outlined,
                            ),
                            const SizedBox(width: 12),
                            _StatCard(
                              label: 'Due This Week',
                              count: upcomingList.length,
                              icon: Icons.inbox_outlined,
                              darker: true,
                              onTap: upcomingList.isNotEmpty
                                  ? () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              UpcomingRenewalsScreen(
                                                  customers: upcomingList),
                                        ),
                                      )
                                  : null,
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // ── Balance Card ──
                        _BalanceCard(
                          totalDue: _totalDue,
                          onTap: _totalDue > 0
                              ? () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => BalanceDueScreen(
                                        customers: _customers
                                            .where((c) => c.due > 0)
                                            .toList(),
                                      ),
                                    ),
                                  )
                              : null,
                        ),

                        const SizedBox(height: 24),

                        // ── Today's urgent list ──
                        if (todayList.isNotEmpty &&
                            _searchQuery.isEmpty &&
                            !_filter.isActive) ...[
                          const Text("Today's Renewals",
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textDark)),
                          const SizedBox(height: 12),
                          ...todayList.map((c) => _CustomerCard(
                                customer: c,
                                urgent: true,
                                onDelete: () =>
                                    _deleteCustomer(_customers.indexOf(c)),
                                onEdit: () async {
                                  final updated =
                                      await Navigator.push<Customer>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          AddCustomerScreen(existing: c),
                                    ),
                                  );
                                  if (updated != null) {
                                    _editCustomer(
                                        _customers.indexOf(c), updated);
                                  }
                                },
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        CustomerDetailScreen(customer: c),
                                  ),
                                ),
                              )),
                          const SizedBox(height: 24),
                        ],

                        // ── All Customers header ──
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _searchQuery.isEmpty && !_filter.isActive
                                  ? 'All Customers'
                                  : 'Filtered Results',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textDark),
                            ),
                            Text('${filtered.length} found',
                                style: const TextStyle(
                                    color: AppColors.textGrey, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // ── Customer list ──
                        filtered.isEmpty
                            ? const _EmptyState()
                            : Column(
                                children: List.generate(
                                  filtered.length,
                                  (i) => _CustomerCard(
                                    customer: filtered[i],
                                    urgent: _isDueToday(filtered[i]),
                                    onDelete: () => _deleteCustomer(
                                        _customers.indexOf(filtered[i])),
                                    onEdit: () async {
                                      final updated =
                                          await Navigator.push<Customer>(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => AddCustomerScreen(
                                              existing: filtered[i]),
                                        ),
                                      );
                                      if (updated != null) {
                                        _editCustomer(
                                            _customers.indexOf(filtered[i]),
                                            updated);
                                      }
                                    },
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => CustomerDetailScreen(
                                            customer: filtered[i]),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ),

                // ── Footer ──
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Developed by Sikandar Ansari',
                    style: TextStyle(fontSize: 11, color: AppColors.textGrey),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final customer = await Navigator.push<Customer>(
            context,
            MaterialPageRoute(builder: (_) => const AddCustomerScreen()),
          );
          if (customer != null) _addCustomer(customer);
        },
        backgroundColor: AppColors.primary,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Client',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15)),
      ),
    );
  }
}

// ─── App Drawer ───────────────────────────────────────────────────────────────

class AppDrawer extends StatelessWidget {
  final VoidCallback onImportCSV;
  final VoidCallback onExportCSV;

  const AppDrawer({
    super.key,
    required this.onImportCSV,
    required this.onExportCSV,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
            decoration: const BoxDecoration(
              color: AppColors.primary,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.local_fire_department,
                      size: 32, color: Colors.white),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Home Care Service',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  'Customer Management App',
                  style: TextStyle(
                      fontSize: 12, color: Colors.white.withOpacity(0.8)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          _drawerItem(
            icon: Icons.home_outlined,
            label: 'Home',
            onTap: () => Navigator.pop(context),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Divider(),
          ),

          const Padding(
            padding: EdgeInsets.only(left: 16, top: 4, bottom: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'DATA',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),

          _drawerItem(
            icon: Icons.upload_file_outlined,
            label: 'Import CSV',
            subtitle: 'Add customers from file',
            onTap: onImportCSV,
          ),

          _drawerItem(
            icon: Icons.download_outlined,
            label: 'Export CSV',
            subtitle: 'Save backup to Downloads',
            onTap: onExportCSV,
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Divider(),
          ),

          _drawerItem(
            icon: Icons.contact_support_outlined,
            label: 'Contact Us',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ContactUsScreen()),
              );
            },
          ),

          const Spacer(),

          const Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: Text(
              'Developed by Sikandar Ansari',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String label,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.grey))
          : null,
      onTap: onTap,
    );
  }
}

// ─── Contact Us Screen ────────────────────────────────────────────────────────

class ContactUsScreen extends StatelessWidget {
  const ContactUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Contact Us',
            style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Get in touch',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'For support, license keys, or any questions:',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            _contactCard(
              icon: Icons.chat,
              iconColor: const Color(0xFF25D366),
              label: 'WhatsApp',
              value: '+91 7019348778',
            ),
            const SizedBox(height: 12),
            _contactCard(
              icon: Icons.email_outlined,
              iconColor: const Color(0xFF2E7D32),
              label: 'Email',
              value: 'supportpanchet@gmail.com',
            ),
            const Spacer(),
            const Center(
              child: Text(
                'Developed by Sikandar Ansari',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _contactCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── WhatsApp Helper ──────────────────────────────────────────────────────────

Future<void> _sendWhatsApp(String phone, String name, String renewalDate) async {
  final message = Uri.encodeComponent(
    'नमस्ते $name जी 🙏\n\n'
    'आपके गैस सिलेंडर की रिन्यूअल डेट $renewalDate है।\n'
    'कृपया समय पर रिन्यूअल करवा लें।\n\n'
    'धन्यवाद 🙏\n- Home Care Service'
  );
  final cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');
  final number = cleaned.startsWith('91') ? cleaned : '91$cleaned';

  final whatsappUrl = Uri.parse('whatsapp://send?phone=$number&text=$message');
  final fallbackUrl = Uri.parse('https://wa.me/$number?text=$message');

  if (await canLaunchUrl(whatsappUrl)) {
    await launchUrl(whatsappUrl);
  } else {
    await launchUrl(fallbackUrl, mode: LaunchMode.externalApplication);
  }
}

// ─── Upcoming Renewals Screen ─────────────────────────────────────────────────

class UpcomingRenewalsScreen extends StatelessWidget {
  final List<Customer> customers;
  const UpcomingRenewalsScreen({super.key, required this.customers});

  @override
  Widget build(BuildContext context) {
    final sorted = [...customers]
      ..sort((a, b) => a.renewalDate.compareTo(b.renewalDate));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Due This Week',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              '${customers.length} customer${customers.length == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sorted.length,
        itemBuilder: (context, i) {
          final c = sorted[i];
          final daysLeft = c.renewalDate.difference(DateTime.now()).inDays;
          final renewalStr =
              '${c.renewalDate.day}/${c.renewalDate.month}/${c.renewalDate.year}';

          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => CustomerDetailScreen(customer: c)),
            ),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: const Color(0xFFF57C00).withOpacity(0.4),
                    width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: const Color(0xFFFFF3E0),
                        child: Text(c.name[0].toUpperCase(),
                            style: const TextStyle(
                                color: Color(0xFFF57C00),
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15)),
                            Text(c.phone,
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 13)),
                            if (c.due > 0)
                              Text('₹${c.due.toStringAsFixed(0)} due',
                                  style: const TextStyle(
                                      color: Color(0xFF1A237E),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            renewalStr,
                            style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFFF57C00),
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3E0),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              daysLeft <= 0
                                  ? 'Tomorrow'
                                  : 'In $daysLeft day${daysLeft == 1 ? '' : 's'}',
                              style: const TextStyle(
                                  color: Color(0xFFF57C00), fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 8),

                  // ── WhatsApp Button ──
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _sendWhatsApp(c.phone, c.name, renewalStr),
                      icon: const Icon(Icons.chat, size: 16),
                      label: const Text('रिन्यूअल रिमाइंडर भेजें',
                          style: TextStyle(fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Active Filter Chips ──────────────────────────────────────────────────────

class _ActiveFilterChips extends StatelessWidget {
  final CustomerFilter filter;
  final VoidCallback onClear;
  final VoidCallback onRemoveDues;
  final VoidCallback onRemoveFrom;
  final VoidCallback onRemoveTo;

  const _ActiveFilterChips({
    required this.filter,
    required this.onClear,
    required this.onRemoveDues,
    required this.onRemoveFrom,
    required this.onRemoveTo,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        if (filter.duesFilter == DuesFilter.hasDues)
          _chip('💰 Has Dues', onRemoveDues),
        if (filter.duesFilter == DuesFilter.noDues)
          _chip('✅ No Dues', onRemoveDues),
        if (filter.renewalFrom != null)
          _chip(
              'From ${filter.renewalFrom!.day}/${filter.renewalFrom!.month}/${filter.renewalFrom!.year}',
              onRemoveFrom),
        if (filter.renewalTo != null)
          _chip(
              'To ${filter.renewalTo!.day}/${filter.renewalTo!.month}/${filter.renewalTo!.year}',
              onRemoveTo),
        GestureDetector(
          onTap: onClear,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text('Clear All',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w500)),
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close,
                size: 14, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

// ─── Filter Bottom Sheet ──────────────────────────────────────────────────────

class FilterSheet extends StatefulWidget {
  final CustomerFilter current;
  const FilterSheet({super.key, required this.current});

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late CustomerFilter _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.current.copyWith();
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom
          ? (_filter.renewalFrom ?? DateTime.now())
          : (_filter.renewalTo ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme:
              const ColorScheme.light(primary: Color(0xFF2E7D32)),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _filter = _filter.copyWith(renewalFrom: picked);
        } else {
          _filter = _filter.copyWith(renewalTo: picked);
        }
      });
    }
  }

  String _fmt(DateTime? d) =>
      d == null ? 'Select date' : '${d.day}/${d.month}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Filter Customers',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              TextButton(
                onPressed: () =>
                    setState(() => _filter = CustomerFilter()),
                child: const Text('Reset',
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Balance Due',
              style:
                  TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 10),
          Row(
            children: [
              _duesChip('All', DuesFilter.all),
              const SizedBox(width: 8),
              _duesChip('Has Dues', DuesFilter.hasDues),
              const SizedBox(width: 8),
              _duesChip('No Dues', DuesFilter.noDues),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Renewal Date Range',
              style:
                  TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _dateTile(
                  label: 'From',
                  value: _fmt(_filter.renewalFrom),
                  hasValue: _filter.renewalFrom != null,
                  onTap: () => _pickDate(true),
                  onClear: () => setState(() => _filter =
                      _filter.copyWith(clearRenewalFrom: true)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _dateTile(
                  label: 'To',
                  value: _fmt(_filter.renewalTo),
                  hasValue: _filter.renewalTo != null,
                  onTap: () => _pickDate(false),
                  onClear: () => setState(() => _filter =
                      _filter.copyWith(clearRenewalTo: true)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, _filter),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Apply Filters',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _duesChip(String label, DuesFilter value) {
    final selected = _filter.duesFilter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(
            () => _filter = _filter.copyWith(duesFilter: value)),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF2E7D32) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xFF2E7D32)
                  : Colors.grey.shade300,
            ),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  color: selected ? Colors.white : Colors.black87,
                  fontWeight: selected
                      ? FontWeight.w600
                      : FontWeight.normal)),
        ),
      ),
    );
  }

  Widget _dateTile({
    required String label,
    required String value,
    required bool hasValue,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: hasValue
              ? const Color(0xFFE8F5E9)
              : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasValue
                ? const Color(0xFF2E7D32)
                : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today,
                size: 16,
                color: hasValue
                    ? const Color(0xFF2E7D32)
                    : Colors.grey),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          color: hasValue
                              ? const Color(0xFF2E7D32)
                              : Colors.grey)),
                  Text(value,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: hasValue
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: hasValue
                              ? const Color(0xFF2E7D32)
                              : Colors.grey)),
                ],
              ),
            ),
            if (hasValue)
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close,
                    size: 16, color: AppColors.primary),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Stat Card ────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final bool darker;
  final VoidCallback? onTap;

  const _StatCard({
    required this.label,
    required this.count,
    required this.icon,
    this.darker = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = darker ? AppColors.cardGreenDark : AppColors.cardGreen;
    final iconColor = darker ? Colors.white : AppColors.primary;
    final textColor = darker ? Colors.white : AppColors.primary;
    final subColor = darker
        ? Colors.white.withOpacity(0.8)
        : AppColors.primary.withOpacity(0.7);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: iconColor, size: 28),
                  if (onTap != null)
                    Icon(Icons.arrow_forward_ios,
                        size: 12, color: iconColor.withOpacity(0.6)),
                ],
              ),
              const SizedBox(height: 10),
              Text('$count',
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: textColor)),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(fontSize: 12, color: subColor)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Balance Card ─────────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  final double totalDue;
  final VoidCallback? onTap;

  const _BalanceCard({required this.totalDue, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const Icon(Icons.account_balance_wallet_outlined,
                color: Colors.white, size: 30),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total Balance Due',
                    style: TextStyle(fontSize: 12, color: Colors.white70)),
                const SizedBox(height: 4),
                Text('₹${totalDue.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ],
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: totalDue > 0
                    ? AppColors.cardGreenDark.withOpacity(0.45)
                    : Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: Colors.white.withOpacity(0.2), width: 1),
              ),
              child: Text(
                totalDue > 0 ? 'Review All' : 'All Clear',
                style: TextStyle(
                    color: totalDue > 0 ? Colors.white : Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Customer Card ────────────────────────────────────────────────────────────

class _CustomerCard extends StatelessWidget {
  final Customer customer;
  final bool urgent;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onTap;

  const _CustomerCard({
    required this.customer,
    required this.urgent,
    required this.onDelete,
    required this.onEdit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: urgent
              ? Border.all(color: AppColors.primary, width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: urgent
                  ? const Color(0xFF2E7D32)
                  : const Color(0xFFE8F5E9),
              child: Text(customer.name[0].toUpperCase(),
                  style: TextStyle(
                      color: urgent
                          ? Colors.white
                          : const Color(0xFF2E7D32),
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(customer.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(customer.phone,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 13)),
                  if (customer.due > 0)
                    Text('₹${customer.due.toStringAsFixed(0)} due',
                        style: const TextStyle(
                            color: Color(0xFF1A237E),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${customer.renewalDate.day}/${customer.renewalDate.month}/${customer.renewalDate.year}',
                  style: TextStyle(
                      fontSize: 12,
                      color: urgent
                          ? const Color(0xFF2E7D32)
                          : Colors.grey,
                      fontWeight: urgent
                          ? FontWeight.bold
                          : FontWeight.normal),
                ),
                if (urgent)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Due Today',
                        style: TextStyle(
                            color: Colors.white, fontSize: 10)),
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined,
                          color: AppColors.primary, size: 20),
                      onPressed: onEdit,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.redAccent, size: 20),
                      onPressed: onDelete,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.cardGreen,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.person_outline,
              size: 64, color: AppColors.primary.withOpacity(0.4)),
          const SizedBox(height: 16),
          const Text(
            "You haven't added any clients yet.",
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            "Get started by tapping the Add Client button.",
            style: TextStyle(fontSize: 13, color: AppColors.textGrey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Customer Detail Screen ───────────────────────────────────────────────────

class CustomerDetailScreen extends StatelessWidget {
  final Customer customer;
  const CustomerDetailScreen({super.key, required this.customer});

  @override
  Widget build(BuildContext context) {
    final bool isDueToday = () {
      final today = DateTime.now();
      return customer.renewalDate.year == today.year &&
          customer.renewalDate.month == today.month &&
          customer.renewalDate.day == today.day;
    }();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Customer Details',
            style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    child: Text(customer.name[0].toUpperCase(),
                        style: const TextStyle(
                            fontSize: 32,
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  Text(customer.name,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(customer.phone,
                      style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.8))),
                  if (isDueToday) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('🔔 Renewal Due Today',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _DetailTile(
                      icon: Icons.numbers,
                      label: 'Consumer Number',
                      value: customer.consumerNumber),
                  const Divider(height: 1, indent: 56),
                  _DetailTile(
                      icon: Icons.location_on,
                      label: 'Address',
                      value: customer.address),
                  const Divider(height: 1, indent: 56),
                  _DetailTile(
                      icon: Icons.shopping_bag_outlined,
                      label: 'Purchase Date',
                      value:
                          '${customer.purchaseDate.day}/${customer.purchaseDate.month}/${customer.purchaseDate.year}'),
                  const Divider(height: 1, indent: 56),
                  _DetailTile(
                      icon: Icons.event_repeat,
                      label: 'Renewal Date',
                      value:
                          '${customer.renewalDate.day}/${customer.renewalDate.month}/${customer.renewalDate.year}',
                      valueColor:
                          isDueToday ? const Color(0xFF2E7D32) : null),
                  const Divider(height: 1, indent: 56),
                  _DetailTile(
                      icon: Icons.account_balance_wallet,
                      label: 'Balance Due',
                      value: '₹${customer.due.toStringAsFixed(2)}',
                      valueColor: customer.due > 0
                          ? const Color(0xFF1A237E)
                          : const Color(0xFF2E7D32)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Detail Tile ──────────────────────────────────────────────────────────────

class _DetailTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: valueColor ?? Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Add / Edit Customer Screen ───────────────────────────────────────────────

class AddCustomerScreen extends StatefulWidget {
  final Customer? existing;
  const AddCustomerScreen({super.key, this.existing});

  @override
  State<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends State<AddCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _consumerNumberController;
  late final TextEditingController _addressController;
  late final TextEditingController _phoneController;
  late final TextEditingController _dueController;
  DateTime? _purchaseDate;
  DateTime? _renewalDate;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _consumerNumberController =
        TextEditingController(text: e?.consumerNumber ?? '');
    _addressController = TextEditingController(text: e?.address ?? '');
    _phoneController = TextEditingController(text: e?.phone ?? '');
    _dueController = TextEditingController(
        text: e != null && e.due > 0 ? e.due.toStringAsFixed(2) : '');
    _purchaseDate = e?.purchaseDate;
    _renewalDate = e?.renewalDate;
  }

  Future<void> _pickDate(bool isRenewal) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: isRenewal ? DateTime(2030) : DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme:
              const ColorScheme.light(primary: Color(0xFF2E7D32)),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isRenewal) {
          _renewalDate = picked;
        } else {
          _purchaseDate = picked;
        }
      });
    }
  }

  void _submit() {
    if (_formKey.currentState!.validate() &&
        _purchaseDate != null &&
        _renewalDate != null) {
      final customer = Customer(
        name: _nameController.text.trim(),
        consumerNumber: _consumerNumberController.text.trim(),
        address: _addressController.text.trim(),
        phone: _phoneController.text.trim(),
        purchaseDate: _purchaseDate!,
        renewalDate: _renewalDate!,
        due: double.tryParse(_dueController.text.trim()) ?? 0.0,
      );
      Navigator.pop(context, customer);
    } else if (_purchaseDate == null || _renewalDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both dates')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Text(isEditing ? 'Edit Customer' : 'Add Customer',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildCard([
                _buildField(_nameController, 'Customer Name', Icons.person),
                _buildField(_consumerNumberController, 'Consumer Number',
                    Icons.numbers),
                _buildPhoneField(),
                _buildField(_addressController, 'Address', Icons.location_on,
                    maxLines: 2),
                _buildDueField(),
              ]),
              const SizedBox(height: 16),
              _buildCard([
                _DatePickerTile(
                  label: 'Purchase Date',
                  date: _purchaseDate,
                  onTap: () => _pickDate(false),
                ),
                const Divider(height: 1),
                _DatePickerTile(
                  label: 'Renewal Date',
                  date: _renewalDate,
                  onTap: () => _pickDate(true),
                ),
              ]),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                      isEditing ? 'Update Customer' : 'Save Customer',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildPhoneField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextFormField(
        controller: _phoneController,
        keyboardType: TextInputType.phone,
        maxLength: 10,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        decoration: const InputDecoration(
          labelText: 'Phone Number',
          prefixIcon: Icon(Icons.phone, color: AppColors.primary),
          border: InputBorder.none,
          counterText: '',
        ),
        validator: (v) {
          if (v == null || v.isEmpty) return 'Phone number is required';
          final digits = v.replaceAll(RegExp(r'\D'), '');
          if (digits.length < 10) {
            return 'Phone number must be at least 10 digits';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildDueField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextFormField(
        controller: _dueController,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Balance Due (₹)',
          prefixIcon: Icon(Icons.account_balance_wallet,
              color: AppColors.primary),
          border: InputBorder.none,
          hintText: '0.00',
        ),
        validator: (v) {
          if (v == null || v.isEmpty) return null;
          if (double.tryParse(v) == null) return 'Enter a valid amount';
          return null;
        },
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: AppColors.primary),
          border: InputBorder.none,
        ),
        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
      ),
    );
  }
}

// ─── Date Picker Tile ─────────────────────────────────────────────────────────

class _DatePickerTile extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  const _DatePickerTile({
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading:
          const Icon(Icons.calendar_today, color: AppColors.primary),
      title: Text(label),
      subtitle: Text(
        date != null
            ? '${date!.day}/${date!.month}/${date!.year}'
            : 'Tap to select',
        style: TextStyle(
            color: date != null ? const Color(0xFF2E7D32) : Colors.grey),
      ),
      onTap: onTap,
    );
  }
}

// ─── Balance Due Screen ───────────────────────────────────────────────────────

class BalanceDueScreen extends StatelessWidget {
  final List<Customer> customers;
  const BalanceDueScreen({super.key, required this.customers});

  @override
  Widget build(BuildContext context) {
    final sorted = [...customers]
      ..sort((a, b) => b.due.compareTo(a.due));

    final totalDue = sorted.fold(0.0, (sum, c) => sum + c.due);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Balance Due',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              '${customers.length} customer${customers.length == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Summary banner
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    color: Colors.white, size: 26),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Outstanding',
                        style: TextStyle(fontSize: 12, color: Colors.white70)),
                    const SizedBox(height: 2),
                    Text('₹${totalDue.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ],
                ),
              ],
            ),
          ),

          // List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: sorted.length,
              itemBuilder: (context, i) {
                final c = sorted[i];
                return GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => CustomerDetailScreen(customer: c)),
                  ),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: const Color(0xFFE8EAF6),
                          child: Text(c.name[0].toUpperCase(),
                              style: const TextStyle(
                                  color: AppColors.navy,
                                  fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                              const SizedBox(height: 2),
                              Text(c.phone,
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 13)),
                              Text(c.consumerNumber,
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₹${c.due.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.navy),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8EAF6),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text('Due',
                                  style: TextStyle(
                                      color: AppColors.navy,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
