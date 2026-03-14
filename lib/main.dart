import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE STOY Control',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const BLEHomePage(),
    );
  }
}

class BLEHomePage extends StatefulWidget {
  const BLEHomePage({super.key});

  @override
  State<BLEHomePage> createState() => _BLEHomePageState();
}

class _BLEHomePageState extends State<BLEHomePage> {
  List<ScanResult> scanResults = [];
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? targetCharacteristic;
  bool isScanning = false;
  bool relay1Active = false;
  bool relay2Active = false;
  int? rssi;
  Timer? rssiTimer;

  final String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String characteristicUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses.values.any((element) => element.isDenied)) {
      debugPrint("Warning: Some permissions were denied");
    }
    
    // Check if Bluetooth is ON
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      debugPrint("Warning: Bluetooth adapter is not ON");
    }
  }

  void _startScan() {
    setState(() {
      scanResults.clear();
      isScanning = true;
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        scanResults = results;
      });
    });

    FlutterBluePlus.isScanning.listen((scanning) {
      setState(() {
        isScanning = scanning;
      });
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() {
        connectedDevice = device;
      });

      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid.toString() == serviceUuid) {
          for (var char in service.characteristics) {
            if (char.uuid.toString() == characteristicUuid) {
              setState(() {
                targetCharacteristic = char;
              });
            }
          }
        }
      }

      // Start RSSI timer
      rssiTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        if (connectedDevice != null) {
          try {
            int newRssi = await connectedDevice!.readRssi();
            setState(() {
              rssi = newRssi;
            });
          } catch (e) {
            debugPrint("Error reading RSSI: $e");
          }
        }
      });
    } catch (e) {
      debugPrint("Connection Error: $e");
    }
  }

  Future<void> _toggleRelay1() async {
    if (targetCharacteristic != null) {
      await targetCharacteristic!.write([49]); // '1' in ASCII
      setState(() {
        relay1Active = !relay1Active;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Relay 1 ${relay1Active ? 'ON' : 'OFF'}")),
      );
    }
  }

  Future<void> _toggleRelay2() async {
    if (targetCharacteristic != null) {
      await targetCharacteristic!.write([50]); // '2' in ASCII
      setState(() {
        relay2Active = !relay2Active;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Relay 2 ${relay2Active ? 'ON' : 'OFF'}")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("STOY BLE Control"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: connectedDevice == null ? _buildDeviceList() : _buildControlPanel(),
      floatingActionButton: connectedDevice == null
          ? FloatingActionButton(
              onPressed: isScanning ? null : _startScan,
              child: isScanning ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.search),
            )
          : null,
    );
  }

  Widget _buildDeviceList() {
    return Column(
      children: [
        if (isScanning) const LinearProgressIndicator(),
        Expanded(
          child: ListView.builder(
            itemCount: scanResults.length,
            itemBuilder: (context, index) {
              final result = scanResults[index];
              final deviceName = result.device.platformName.isNotEmpty ? result.device.platformName : "Unknown Device";
              final isStoy = deviceName == "RGEP_STOY";

              return Card(
                color: isStoy ? Colors.green.withOpacity(0.2) : null,
                child: ListTile(
                  leading: Icon(isStoy ? Icons.bluetooth_searching : Icons.bluetooth, color: isStoy ? Colors.green : null),
                  title: Text(deviceName, style: TextStyle(fontWeight: isStoy ? FontWeight.bold : FontWeight.normal)),
                  subtitle: Text(result.device.remoteId.toString()),
                  trailing: ElevatedButton(
                    onPressed: () => _connectToDevice(result.device),
                    child: const Text("Connect"),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildControlPanel() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text("Connected to: ${connectedDevice!.platformName}", style: Theme.of(context).textTheme.headlineSmall),
          if (rssi != null) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.signal_cellular_alt, color: Colors.greenAccent),
                const SizedBox(width: 8),
                Text("Signal: $rssi dBm", style: const TextStyle(fontSize: 18, color: Colors.greenAccent)),
              ],
            ),
          ],
          const SizedBox(height: 40),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _buildRelayButton(
                  title: "RELAY 1",
                  subtitle: "GPIO 26",
                  color: relay1Active ? Colors.blueAccent : Colors.grey,
                  onPressed: targetCharacteristic != null ? _toggleRelay1 : null,
                ),
                const SizedBox(height: 20),
                _buildRelayButton(
                  title: "RELAY 2",
                  subtitle: "GPIO 27",
                  color: relay2Active ? Colors.orangeAccent : Colors.grey,
                  onPressed: targetCharacteristic != null ? _toggleRelay2 : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (targetCharacteristic == null)
            const Text("Characteristic not found!", style: TextStyle(color: Colors.red)),
          const SizedBox(height: 40),
          TextButton(
            onPressed: () async {
              await connectedDevice!.disconnect();
              rssiTimer?.cancel();
              setState(() {
                connectedDevice = null;
                targetCharacteristic = null;
                rssi = null;
              });
            },
            child: const Text("Disconnect"),
          )
        ],
      ),
    );
  }
  Widget _buildRelayButton({
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 20),
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: 5,
        ),
        onPressed: onPressed,
        child: Column(
          children: [
            Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Text(subtitle, style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }
}
