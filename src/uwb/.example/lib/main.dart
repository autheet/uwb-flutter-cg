import 'package:flutter/material.dart';
import 'package:uwb_example/app.dart';
import 'package:uwb_example/navigator_key.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      localizationsDelegates: const [DefaultMaterialLocalizations.delegate],
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      navigatorKey: navigatorKey,
      home: const MyApp(),
    ),
  );
}
