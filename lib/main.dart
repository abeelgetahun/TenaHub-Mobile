import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/webview_screen.dart';

void main() {
  runApp(const TenaHub());
}

class TenaHub extends StatelessWidget {
  const TenaHub({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TenaHub',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.lightBlueAccent,
          foregroundColor: Colors.white,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
      ),
      home: const WebViewScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
