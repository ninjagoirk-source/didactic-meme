import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    debugPrint('Ошибка камеры: $e');
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Drive',
      theme: ThemeData(primarySwatch: Colors.blue),
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
  List<FileSystemEntity> _files = [];

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _loadFiles();
  }

  Future<void> _loadFiles() async {
    if (kIsWeb) return;
    final directory = await getApplicationDocumentsDirectory();
    final dir = Directory(directory.path);
    final files = dir.listSync().where((file) {
      final ext = p.extension(file.path).toLowerCase();
      return ['.jpg', '.mp4', '.pdf', '.docx', '.doc', '.txt'].contains(ext);
    }).toList();

    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

    setState(() {
      _files = files;
    });
  }

  Future<void> _openCamera() async {
    if (cameras.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Камера не найдена')),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CameraScreen(cameras: cameras)),
    );
    _loadFiles();
  }

  Future<void> _pickFile() async {
    try {
      // FileType.any = любые файлы (PDF, Word, TXT, картинки и т.д.)
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: kIsWeb, // для веба нужно загружать байты
      );
      if (result != null) {
        if (kIsWeb) {
          // В вебе просто показываем сообщение (файлы не сохраняются на диск)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Выбран файл: ${result.files.single.name}')),
          );
        } else if (result.files.single.path != null) {
          final sourceFile = File(result.files.single.path!);
          final directory = await getApplicationDocumentsDirectory();
          final fileName = p.basename(sourceFile.path);
          final newPath = p.join(directory.path, fileName);
          await sourceFile.copy(newPath);
          _loadFiles();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Файл добавлен: $fileName')),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Ошибка выбора файла: $e');
    }
  }

  IconData _getFileIcon(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.jpg':
        return Icons.image;
      case '.mp4':
        return Icons.videocam;
      case '.pdf':
        return Icons.picture_as_pdf;
      case '.doc':
      case '.docx':
        return Icons.description;
      default:
        return Icons.insert_drive_file;
    }
  }

  Widget _buildFilePreview(FileSystemEntity file) {
    final ext = p.extension(file.path).toLowerCase();
    // В вебе Image.file не работает, поэтому показываем иконку
    if (kIsWeb) {
      return Icon(_getFileIcon(file.path), size: 50, color: Colors.blueGrey);
    }
    if (ext == '.jpg') {
      return Image.file(File(file.path), fit: BoxFit.cover);
    }
    return Icon(_getFileIcon(file.path), size: 50, color: Colors.blueGrey);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Мой Диск')),
      body: kIsWeb
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  'Веб-версия не поддерживает полный функционал.\n'
                  'Пожалуйста, запустите приложение на реальном Android-телефоне.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
              ),
            )
          : (_files.isEmpty
              ? const Center(child: Text('Нет файлов. Нажмите + чтобы снять или прикрепить.'))
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final file = _files[index];
                    return GestureDetector(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Файл: ${p.basename(file.path)}')),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey[200],
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildFilePreview(file),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                color: Colors.black54,
                                padding: const EdgeInsets.all(2),
                                child: Text(
                                  DateFormat('dd.MM HH:mm')
                                      .format(file.statSync().modified),
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 10),
                                ),
                              ),
                            )
                          ],
                        ),
                      ),
                    );
                  },
                )),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'pickFile',
            backgroundColor: Colors.green,
            onPressed: _pickFile,
            child: const Icon(Icons.attach_file),
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            heroTag: 'camera',
            onPressed: _openCamera,
            child: const Icon(Icons.add_a_photo),
          ),
        ],
      ),
    );
  }
}

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  bool _isRecording = false;
  int _cameraIndex = 0;
  XFile? _capturedImage;

  @override
  void initState() {
    super.initState();
    _initCamera(_cameraIndex);
  }

  Future<void> _initCamera(int index) async {
    _controller = CameraController(widget.cameras[index], ResolutionPreset.high);
    await _controller.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2) return;
    setState(() {
      _cameraIndex = (_cameraIndex + 1) % widget.cameras.length;
    });
    await _controller.dispose();
    await _initCamera(_cameraIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveFile(XFile file) async {
    if (kIsWeb) return; // В вебе не сохраняем на диск
    final directory = await getApplicationDocumentsDirectory();
    final fileName = p.basename(file.path);
    final newPath = p.join(directory.path, fileName);
    await file.saveTo(newPath);
  }

  Future<void> _takePicture() async {
    try {
      final XFile file = await _controller.takePicture();
      setState(() {
        _capturedImage = file;
      });
    } catch (e) {
      debugPrint('$e');
    }
  }

  Future<void> _savePicture() async {
    if (_capturedImage != null) {
      await _saveFile(_capturedImage!);
      if (mounted) Navigator.pop(context);
    }
  }

  void _cancelPicture() {
    setState(() {
      _capturedImage = null;
    });
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final XFile file = await _controller.stopVideoRecording();
      await _saveFile(file);
      setState(() => _isRecording = false);
      if (mounted) Navigator.pop(context);
    } else {
      await _controller.startVideoRecording();
      setState(() => _isRecording = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_capturedImage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Предпросмотр')),
        body: Column(
          children: [
            Expanded(
              child: kIsWeb
                  ? const Center(child: Text('Предпросмотр недоступен в вебе'))
                  : Image.file(File(_capturedImage!.path)),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _cancelPicture,
                    icon: const Icon(Icons.cancel),
                    label: const Text('Отмена'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  ),
                  ElevatedButton.icon(
                    onPressed: _savePicture,
                    icon: const Icon(Icons.save),
                    label: const Text('Сохранить'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Камера'),
        actions: [
          if (widget.cameras.length > 1)
            IconButton(
              icon: const Icon(Icons.flip_camera_ios),
              onPressed: _switchCamera,
            ),
        ],
      ),
      body: Stack(
        children: [
          CameraPreview(_controller),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  FloatingActionButton(
                    heroTag: 'photo',
                    onPressed: _isRecording ? null : _takePicture,
                    child: const Icon(Icons.camera_alt),
                  ),
                  FloatingActionButton(
                    heroTag: 'video',
                    backgroundColor: _isRecording ? Colors.red : Colors.white,
                    onPressed: _toggleRecording,
                    child: Icon(_isRecording ? Icons.stop : Icons.videocam),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}