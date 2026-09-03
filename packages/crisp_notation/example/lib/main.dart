import 'package:flutter/material.dart';
import 'package:crisp_notation/crisp_notation.dart';

import 'dsl_editor.dart';
import 'gallery.dart';
import 'interactive.dart';
import 'jianpu_debug.dart';
import 'jianpu_iso_gallery.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Bravura.load();
  runApp(const CrispNotationExampleApp());
}

class CrispNotationExampleApp extends StatelessWidget {
  const CrispNotationExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'crisp_notation demo',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1E88E5)),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('crisp_notation')),
      body: switch (_index) {
        0 => const GalleryScreen(),
        1 => const InteractiveScreen(),
        2 => const JianpuDebugPage(),
        3 => const JianpuIsoGalleryPage(),
        _ => const DslEditorPage(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view),
            label: 'Gallery',
          ),
          NavigationDestination(
            icon: Icon(Icons.touch_app),
            label: 'Interactive',
          ),
          NavigationDestination(
            icon: Icon(Icons.music_note),
            label: '简谱调试',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book),
            label: '简谱规范',
          ),
          NavigationDestination(
            icon: Icon(Icons.school),
            label: 'Score Editor',
          ),
        ],
      ),
    );
  }
}
