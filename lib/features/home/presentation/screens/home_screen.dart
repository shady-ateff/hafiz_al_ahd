import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(
      //   title: const Text('Hafiz Al Ahd'),
      // ),
      body: const Center(
        child: Center(
          child: Flex(
            direction: Axis.horizontal,
            children: [
              Center(
                child: Text(
                  'Hafiz Al Ahd',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
