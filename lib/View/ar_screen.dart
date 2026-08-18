import 'package:flutter/material.dart';

class ARScreen extends StatelessWidget {
  const ARScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AR')),
      body: const Center(child: Text('AR experience goes here')),
    );
  }
}
