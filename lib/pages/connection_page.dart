import 'package:flutter/material.dart';
import '../views/device_view.dart';

class ConnectionPage extends StatelessWidget {
  const ConnectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("デバイス接続"),
      ),
      body: const DeviceView(),
    );
  }
}