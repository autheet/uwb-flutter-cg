import 'dart:math';

import 'package:flutter/material.dart';
import 'package:uwb/flutter_uwb.dart';
import 'package:uwb_example/pages/ranging_page.dart';
import 'package:uwb_example/pages/localisation_page.dart';
import 'package:uwb_example/settings.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static final Uwb _uwbPlugin = Uwb();

  List<Widget> _pages = [];
  int _selectedPageIndex = 0;
  String _deviceName = '';

  void _onItemTapped(int index) {
    setState(() {
      _selectedPageIndex = index;
    });
  }

  static String generateRandomName() {
    return "device-${Random().nextInt(10000)}";
  }

  @override
  void initState() {
    super.initState();
    _deviceName = generateRandomName();

    _pages = <Widget>[
      RangingPage(uwbPlugin: _uwbPlugin, deviceName: _deviceName),
      LocalisationPage(uwbPlugin: _uwbPlugin, deviceName: _deviceName),
    ];

    uwbDataStream.addStream(_uwbPlugin.uwbDataStream.asBroadcastStream());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UWB Example App'),
        centerTitle: true,
      ),
      body: IndexedStack(
        index: _selectedPageIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Localisation',
          ),
        ],
        currentIndex: _selectedPageIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}
