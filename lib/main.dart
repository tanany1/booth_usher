import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';

void main() {
  runApp(MaterialApp(
    home: BoothApp(),
    debugShowCheckedModeBanner: false,
  ));
}

class BoothApp extends StatefulWidget {
  @override
  _BoothAppState createState() => _BoothAppState();
}

class _BoothAppState extends State<BoothApp> {
  final TextEditingController _pointsController = TextEditingController();
  final TextEditingController _boothNameController =
  TextEditingController(text: "Booth 1");

  String _nfcContent = "No data read yet";

  String userId = "";
  String userName = "";
  String userTitle = "";
  String userPhone = "";
  Map<String, int> boothPoints = {};
  int totalPoints = 0;

  /// -------- NFC Read Function -------------
  Future<void> readCard() async {
    _showNfcDialog("Tap the NFC card", "Hold your NFC card near the device");

    NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
      try {
        var ndef = Ndef.from(tag);
        if (ndef == null || ndef.cachedMessage == null) {
          _showSnackBar("❌ No NDEF data found");
          _closeDialogsAndSession();
          return;
        }

        final record = ndef.cachedMessage!.records.first;
        int languageCodeLength = record.payload.first;
        String payload = String.fromCharCodes(
          record.payload.sublist(1 + languageCodeLength),
        );

        Navigator.pop(context);

        _parsePayload(payload);

        _showSnackBar("✅ Data read successfully!");
      } catch (e) {
        _showSnackBar("❌ Error reading data: $e");
      } finally {
        _closeDialogsAndSession();
      }
    });
  }

  /// -------- Update Points on Card -------------
  Future<void> updatePoints() async {
    if (_pointsController.text.isEmpty || _boothNameController.text.isEmpty) {
      _showSnackBar("⚠️ Enter booth name and points!");
      return;
    }

    int newPoints = int.tryParse(_pointsController.text.trim()) ?? 0;
    String boothName = _boothNameController.text.trim();

    if (boothName.isEmpty || newPoints <= 0) {
      _showSnackBar("⚠️ Invalid booth name or points!");
      return;
    }

    _showNfcDialog("Tap the NFC card", "Hold your NFC card near the device");

    NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
      try {
        var ndef = Ndef.from(tag);
        if (ndef == null || !ndef.isWritable) {
          _showSnackBar("❌ NFC card is not writable");
          _closeDialogsAndSession();
          return;
        }

        print('Tag maxSize: ${ndef.maxSize} bytes');

        final record = ndef.cachedMessage?.records.first;
        String existingPayload = "";
        int languageCodeLength = 0;

        if (record != null && record.payload.isNotEmpty) {
          languageCodeLength = record.payload.first;
          existingPayload = String.fromCharCodes(
            record.payload.sublist(1 + languageCodeLength),
          );
        }

        // Parse old data
        List<String> sections = existingPayload.split('#');
        String userData = sections.isNotEmpty ? sections[0] : "";
        String pointsData = sections.length > 1 ? sections[1] : "";

        Map<String, int> boothPoints = {};
        if (pointsData.isNotEmpty) {
          pointsData.split(';').forEach((entry) {
            if (entry.contains(':')) {
              var pair = entry.split(':');
              boothPoints[pair[0].trim()] = int.tryParse(pair[1].trim()) ?? 0;
            }
          });
        }

        boothPoints[boothName] = (boothPoints[boothName] ?? 0) + newPoints;

        String updatedPointsData =
        boothPoints.entries.map((e) => "${e.key}:${e.value}").join(';');
        String newPayload = "$userData#$updatedPointsData";

        print('New Payload to write: $newPayload');
        print('Payload length: ${utf8.encode(newPayload).length} bytes');

        Uint8List payloadBytes = Uint8List.fromList(utf8.encode(newPayload));

        // Check size BEFORE writing!
        if (payloadBytes.length > ndef.maxSize) {
          Navigator.pop(context); // Close the dialog first if open
          _closeDialogsAndSession();

          _showFullStorageDialog(ndef.maxSize, payloadBytes.length);
          return;
        }

        NdefRecord customRecord = NdefRecord(
          typeNameFormat: NdefTypeNameFormat.nfcWellknown,
          type: Uint8List.fromList([0x54]), // 'T'
          identifier: Uint8List(0),
          payload:
          Uint8List.fromList([0x02] + utf8.encode('en') + payloadBytes),
        );

        NdefMessage message = NdefMessage([customRecord]);

        await ndef.write(message);

        Navigator.pop(context); // Close the waiting NFC dialog
        _parsePayload(newPayload);
        _showSnackBar("✅ Points updated successfully!");
      } catch (e) {
        print("❌ Exception during write: $e");
        _showSnackBar("❌ Failed to write to NFC tag!");
      } finally {
        _closeDialogsAndSession();
      }
    });
  }

  /// -------- Parse payload and update UI state -------------
  void _parsePayload(String payload) {
    try {
      List<String> sections = payload.split('#');

      String userData = sections.isNotEmpty ? sections[0] : "";
      String pointsData = sections.length > 1 ? sections[1] : "";

      // Correctly split user info (pipe-separated: id|name|title|phone)
      List<String> userParts = userData.split('|');

      userId = userParts.isNotEmpty ? userParts[0] : "";
      userName = userParts.length > 1 ? userParts[1] : "";
      userTitle = userParts.length > 2 ? userParts[2] : "";
      userPhone = userParts.length > 3 ? userParts[3] : "";

      // Parse booth points data (unchanged)
      boothPoints.clear();
      if (pointsData.isNotEmpty) {
        pointsData.split(';').forEach((entry) {
          if (entry.contains(':')) {
            var pair = entry.split(':');
            if (pair.length == 2) {
              String name = pair[0].trim();
              int pts = int.tryParse(pair[1].trim()) ?? 0;
              boothPoints[name] = pts;
            }
          }
        });
      }

      totalPoints = boothPoints.values.fold(0, (sum, pts) => sum + pts);

      setState(() {
        _nfcContent = payload;
      });

      print("✅ Parsed userId: $userId, Total Points: $totalPoints");
    } catch (e) {
      print("❌ Exception parsing payload: $e");
      _showSnackBar("❌ Failed to parse data!");
    }
  }


  /// -------- UI Helpers -------------
  void _showNfcDialog(String title, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.nfc, size: 50),
            const SizedBox(height: 10),
            Text(message),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _closeDialogsAndSession() {
    if (Navigator.canPop(context)) Navigator.pop(context);
    NfcManager.instance.stopSession();
  }

  void _showFullStorageDialog(int maxSize, int payloadSize) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Storage Full ❌"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning, color: Colors.red, size: 50),
            const SizedBox(height: 10),
            Text(
              "The NFC tag does not have enough storage space.\n\n"
                  "Max size: ${maxSize} bytes\n"
                  "Your data: ${payloadSize} bytes\n\n"
                  "Please reduce the data or use a larger tag.",
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pointsController.dispose();
    _boothNameController.dispose();
    super.dispose();
  }

  /// -------- UI Layout -------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Booth Points Updater")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _boothNameController,
                decoration: const InputDecoration(labelText: "Booth Name"),
              ),
              TextField(
                controller: _pointsController,
                decoration: const InputDecoration(labelText: "Points to Add"),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: updatePoints,
                icon: const Icon(Icons.system_update_alt),
                label: const Text("Update Points"),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: readCard,
                icon: const Icon(Icons.nfc),
                label: const Text("Read Card Data"),
              ),
              const SizedBox(height: 20),
              const Text(
                "Stored Data:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              _buildUserCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard() {
    if (_nfcContent == "No data read yet" || userId.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(_nfcContent),
      );
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("User ID: $userId",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text("Name: $userName"),
            Text("Title: $userTitle"),
            Text("Phone: $userPhone"),
            const SizedBox(height: 10),
            const Text("Booth Points:",
                style: TextStyle(fontWeight: FontWeight.bold)),
            ...boothPoints.entries
                .map((entry) => Text("${entry.key}: ${entry.value} pts")),
            const Divider(),
            Text("Total Points Collected: $totalPoints",
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
