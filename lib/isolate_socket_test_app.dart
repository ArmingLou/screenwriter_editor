import 'package:flutter/material.dart';
import 'isolate_socket_test.dart';

void main() {
  runApp(const IsolateSocketTestApp());
}

class IsolateSocketTestApp extends StatelessWidget {
  const IsolateSocketTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Isolate Socket Test',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const IsolateSocketTestPage(),
    );
  }
}
