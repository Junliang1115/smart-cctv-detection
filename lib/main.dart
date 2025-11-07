import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'dart:io' show Platform;
import 'pages/live_feed_windows.dart';
import 'pages/upload_video.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    // ignore: avoid_print
    print('Error fetching cameras: $e');
    cameras = [];
  } on MissingPluginException catch (e) {
    print('Camera plugin not implemented on this platform: $e');
    cameras = [];
  } catch (e) {
    print('Unknown error fetching cameras: $e');
    cameras = [];
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart CCTV',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Smart CCTV'),
      routes: {
        '/live':
            (ctx) => Scaffold(
              appBar: AppBar(title: const Text('Live Feed')),
              body: const Center(
                child: Text(
                  'Live feed page removed. Use the desktop view or upload a video.',
                ),
              ),
            ),
      },
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              onPressed: () {
                try {
                  if (Platform.isWindows) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LiveFeedWindows(),
                      ),
                    );
                    return;
                  }
                } catch (_) {}
                Navigator.of(context).pushNamed('/live');
              },
              icon: const Icon(Icons.videocam),
              label: const Text('Open Live Feed'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const UploadVideoPage()),
                );
              },
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload Video'),
            ),
          ],
        ),
      ),
    );
  }
}
