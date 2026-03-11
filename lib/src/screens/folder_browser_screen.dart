import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:video_player/video_player.dart';

import '../models/hidden_folder_entry.dart';
import '../models/vault_item.dart';
import '../state/vault_controller.dart';

class FolderBrowserScreen extends StatefulWidget {
  const FolderBrowserScreen({
    required this.controller,
    required this.folder,
    super.key,
  });

  final VaultController controller;
  final VaultItem folder;

  @override
  State<FolderBrowserScreen> createState() => _FolderBrowserScreenState();
}

class _FolderBrowserScreenState extends State<FolderBrowserScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final entries = widget.controller.folderEntries(widget.folder);
    final filteredEntries = entries.where((entry) {
      if (_query.trim().isEmpty) {
        return true;
      }
      final normalizedQuery = _query.trim().toLowerCase();
      return entry.relativePath.toLowerCase().contains(normalizedQuery);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.folder.title),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search inside folder',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          Expanded(
            child: filteredEntries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        entries.isEmpty
                            ? 'This hidden folder has no readable entries.'
                            : 'No files match your search.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: filteredEntries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final entry = filteredEntries[index];
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Icon(_iconForEntry(entry)),
                          ),
                          title: Text(entry.name),
                          subtitle: Text(
                            [
                              if (entry.directory.isNotEmpty) entry.directory,
                              _formatBytes(entry.sizeBytes),
                            ].join('  |  '),
                          ),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => FolderEntryPreviewScreen(
                                  controller: widget.controller,
                                  folder: widget.folder,
                                  entry: entry,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class FolderEntryPreviewScreen extends StatelessWidget {
  const FolderEntryPreviewScreen({
    required this.controller,
    required this.folder,
    required this.entry,
    super.key,
  });

  final VaultController controller;
  final VaultItem folder;
  final HiddenFolderEntry entry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(entry.name),
      ),
      body: FutureBuilder<Uint8List>(
        future: controller.readFolderEntryBytes(entry),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not open this file securely.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final bytes = snapshot.data;
          if (bytes == null) {
            return const Center(child: Text('No data available.'));
          }

          if (entry.isImage) {
            return InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Center(
                child: Image.memory(bytes),
              ),
            );
          }

          if (entry.isPdf) {
            return SfPdfViewer.memory(bytes);
          }

          if (entry.isVideo) {
            return _SecureVideoPreview(entry: entry, bytes: bytes);
          }

          if (entry.isText) {
            final text = utf8.decode(bytes, allowMalformed: true);
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.5,
                    ),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Secure file details',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 16),
                _DetailRow(label: 'Folder', value: folder.title),
                _DetailRow(label: 'Path', value: entry.relativePath),
                _DetailRow(label: 'Size', value: _formatBytes(entry.sizeBytes)),
                _DetailRow(label: 'Type', value: entry.extension.isEmpty ? 'Unknown' : entry.extension),
                const SizedBox(height: 24),
                Text(
                  'Preview is currently available for images, PDFs, videos, and text-based files. Use Unhide to restore other file types through the parent folder when needed.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SecureVideoPreview extends StatefulWidget {
  const _SecureVideoPreview({
    required this.entry,
    required this.bytes,
  });

  final HiddenFolderEntry entry;
  final Uint8List bytes;

  @override
  State<_SecureVideoPreview> createState() => _SecureVideoPreviewState();
}

class _SecureVideoPreviewState extends State<_SecureVideoPreview> {
  VideoPlayerController? _controller;
  File? _tempFile;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        path.join(
          tempDir.path,
          'orbit_tap_preview_${DateTime.now().microsecondsSinceEpoch}${widget.entry.extension}',
        ),
      );
      await tempFile.writeAsBytes(widget.bytes, flush: true);

      final controller = VideoPlayerController.file(tempFile);
      await controller.initialize();
      await controller.setLooping(false);

      if (!mounted) {
        await controller.dispose();
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (_) {
          // Best effort cleanup only.
        }
        return;
      }

      setState(() {
        _tempFile = tempFile;
        _controller = controller;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    final tempFile = _tempFile;
    if (controller != null) {
      controller.dispose();
    }
    if (tempFile != null) {
      Future<void>(() async {
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (_) {
          // Best effort cleanup only.
        }
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not load this video securely.\n$_error',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: Text('Video preview is unavailable.'));
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AspectRatio(
            aspectRatio: controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: VideoPlayer(controller),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                onPressed: () async {
                  final position = await controller.position ?? Duration.zero;
                  final rewindTo = position - const Duration(seconds: 5);
                  await controller.seekTo(rewindTo < Duration.zero ? Duration.zero : rewindTo);
                },
                icon: const Icon(Icons.replay_5),
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                onPressed: () {
                  if (controller.value.isPlaying) {
                    controller.pause();
                  } else {
                    controller.play();
                  }
                  setState(() {});
                },
                icon: Icon(controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
              ),
              const SizedBox(width: 12),
              IconButton.filledTonal(
                onPressed: () async {
                  final position = await controller.position ?? Duration.zero;
                  final forwardTo = position + const Duration(seconds: 5);
                  final duration = controller.value.duration;
                  await controller.seekTo(forwardTo > duration ? duration : forwardTo);
                },
                icon: const Icon(Icons.forward_5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final duration = value.duration;
              final position = value.position > duration ? duration : value.position;
              return Column(
                children: [
                  Slider(
                    value: duration.inMilliseconds == 0
                        ? 0
                        : position.inMilliseconds / duration.inMilliseconds,
                    onChanged: (newValue) async {
                      final newPosition = Duration(
                        milliseconds: (duration.inMilliseconds * newValue).round(),
                      );
                      await controller.seekTo(newPosition);
                    },
                  ),
                  Text('${_formatDuration(position)} / ${_formatDuration(duration)}'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          Text(value),
        ],
      ),
    );
  }
}

IconData _iconForEntry(HiddenFolderEntry entry) {
  if (entry.isImage) {
    return Icons.image_outlined;
  }
  if (entry.isText) {
    return Icons.description_outlined;
  }
  if (entry.isPdf) {
    return Icons.picture_as_pdf_outlined;
  }
  if (entry.extension == '.zip' || entry.extension == '.rar' || entry.extension == '.7z') {
    return Icons.archive_outlined;
  }
  if (entry.isVideo) {
    return Icons.movie_outlined;
  }
  return Icons.insert_drive_file_outlined;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}


