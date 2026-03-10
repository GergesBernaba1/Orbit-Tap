import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/device_contact.dart';
import '../models/installed_app.dart';
import '../models/vault_item.dart';
import '../state/vault_controller.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.controller,
    super.key,
  });

  final VaultController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _titles = [
    'Overview',
    'Images',
    'Videos',
    'Contacts',
    'Apps',
  ];

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final message = widget.controller.errorMessage;
    if (message != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
        widget.controller.clearError();
      });
    }
  }

  Future<void> _onFabPressed() async {
    switch (_index) {
      case 1:
        await widget.controller.importImages();
        break;
      case 2:
        await widget.controller.importVideos();
        break;
      case 3:
        await _showContactPicker();
        break;
      case 4:
        await _showAppPicker();
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _OverviewPage(controller: widget.controller),
      _VaultListPage(
        emptyMessage: 'Import photos or screenshots into the private vault.',
        items: widget.controller.itemsFor(VaultItemType.image),
        controller: widget.controller,
      ),
      _VaultListPage(
        emptyMessage: 'Import private videos into encrypted app storage.',
        items: widget.controller.itemsFor(VaultItemType.video),
        controller: widget.controller,
      ),
      _ContactsPage(controller: widget.controller),
      _AppsPage(controller: widget.controller),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(
            onPressed: widget.controller.lock,
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Lock vault',
          ),
        ],
      ),
      body: Stack(
        children: [
          IndexedStack(index: _index, children: pages),
          if (widget.controller.busy)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
      floatingActionButton: _index == 0
          ? null
          : FloatingActionButton.extended(
              onPressed: widget.controller.busy ? null : _onFabPressed,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.photo_library_outlined), label: 'Images'),
          NavigationDestination(icon: Icon(Icons.movie_outlined), label: 'Videos'),
          NavigationDestination(icon: Icon(Icons.contacts_outlined), label: 'Contacts'),
          NavigationDestination(icon: Icon(Icons.apps_outlined), label: 'Apps'),
        ],
      ),
    );
  }

  Future<void> _showContactPicker() async {
    List<DeviceContact> contacts;
    try {
      contacts = await widget.controller.loadDeviceContacts();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
      return;
    }

    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.8,
            child: _SelectableContactList(
              contacts: contacts,
              onSelected: (contact) async {
                Navigator.of(context).pop();
                await widget.controller.addHiddenContact(contact);
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAppPicker() async {
    List<InstalledAppModel> apps;
    try {
      apps = await widget.controller.loadInstalledApps();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
      return;
    }

    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.8,
            child: _SelectableAppList(
              apps: apps,
              onSelected: (app) async {
                Navigator.of(context).pop();
                await widget.controller.addPrivateApp(app);
              },
            ),
          ),
        );
      },
    );
  }
}

class _OverviewPage extends StatelessWidget {
  const _OverviewPage({required this.controller});

  final VaultController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xFF003049), Color(0xFF669BBC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Private vault',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Media is encrypted locally. Contacts and app entries stay behind the same vault lock.',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _StatCard(label: 'Images', value: controller.countFor(VaultItemType.image).toString()),
            _StatCard(label: 'Videos', value: controller.countFor(VaultItemType.video).toString()),
            _StatCard(label: 'Contacts', value: controller.countFor(VaultItemType.contact).toString()),
            _StatCard(label: 'Apps', value: controller.countFor(VaultItemType.app).toString()),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Platform note',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  controller.appsFeatureSupported
                      ? 'Android supports a private in-app launcher list here. True launcher hiding still requires special device privileges.'
                      : 'On iOS, app vault entries are informational only because the platform restricts other app access.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              const SizedBox(height: 6),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VaultListPage extends StatelessWidget {
  const _VaultListPage({
    required this.emptyMessage,
    required this.items,
    required this.controller,
  });

  final String emptyMessage;
  final List<VaultItem> items;
  final VaultController controller;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        final isImage = item.type == VaultItemType.image;

        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: isImage
                ? _ImagePreview(controller: controller, item: item)
                : const _VideoPreview(),
            title: Text(item.title),
            subtitle: Text(
              [
                item.subtitle,
                if (item.sizeBytes != null) _formatBytes(item.sizeBytes!),
                DateFormat('MMM d, yyyy').format(item.createdAt),
              ].join('  |  '),
            ),
            trailing: IconButton(
              onPressed: () => controller.deleteItem(item),
              icon: const Icon(Icons.delete_outline),
            ),
          ),
        );
      },
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({
    required this.controller,
    required this.item,
  });

  final VaultController controller;
  final VaultItem item;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: controller.readMediaBytes(item),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              snapshot.data!,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
            ),
          );
        }

        return Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.photo),
        );
      },
    );
  }
}

class _VideoPreview extends StatelessWidget {
  const _VideoPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.movie),
    );
  }
}

class _ContactsPage extends StatelessWidget {
  const _ContactsPage({required this.controller});

  final VaultController controller;

  @override
  Widget build(BuildContext context) {
    final contacts = controller.itemsFor(VaultItemType.contact);
    if (contacts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Pull selected contacts into the vault so their details stay behind one app lock.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: contacts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = contacts[index];
        final phones = (item.metadata['phones'] as List<dynamic>? ?? const []).cast<String>();
        final emails = (item.metadata['emails'] as List<dynamic>? ?? const []).cast<String>();
        final details = [
          if (phones.isNotEmpty) phones.first,
          if (emails.isNotEmpty) emails.first,
        ].join('  |  ');

        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              child: Text(item.title.isNotEmpty ? item.title[0].toUpperCase() : '?'),
            ),
            title: Text(item.title),
            subtitle: Text(details.isEmpty ? 'Stored privately inside vault' : details),
            trailing: IconButton(
              onPressed: () => controller.deleteItem(item),
              icon: const Icon(Icons.delete_outline),
            ),
          ),
        );
      },
    );
  }
}

class _AppsPage extends StatelessWidget {
  const _AppsPage({required this.controller});

  final VaultController controller;

  @override
  Widget build(BuildContext context) {
    final apps = controller.itemsFor(VaultItemType.app);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              controller.appsFeatureSupported
                  ? 'These entries create a private app list inside the vault. They do not remove apps from the system launcher.'
                  : 'This device cannot enumerate and launch installed apps through the current platform layer.',
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (apps.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Add apps to maintain a private launcher list behind your passcode.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          )
        else
          ...apps.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: const CircleAvatar(child: Icon(Icons.apps)),
                  title: Text(item.title),
                  subtitle: Text(item.subtitle),
                  onTap: controller.appsFeatureSupported
                      ? () => controller.openPrivateApp(item)
                      : null,
                  trailing: IconButton(
                    onPressed: () => controller.deleteItem(item),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SelectableContactList extends StatelessWidget {
  const _SelectableContactList({
    required this.contacts,
    required this.onSelected,
  });

  final List<DeviceContact> contacts;
  final ValueChanged<DeviceContact> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Select contact',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: contacts.length,
            itemBuilder: (context, index) {
              final contact = contacts[index];
              final details = [
                if (contact.phones.isNotEmpty) contact.phones.first,
                if (contact.emails.isNotEmpty) contact.emails.first,
              ].join('  |  ');

              return ListTile(
                leading: CircleAvatar(
                  child: Text(
                    contact.displayName.isNotEmpty
                        ? contact.displayName[0].toUpperCase()
                        : '?',
                  ),
                ),
                title: Text(contact.displayName),
                subtitle: Text(details.isEmpty ? 'No phone or email' : details),
                onTap: () => onSelected(contact),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SelectableAppList extends StatelessWidget {
  const _SelectableAppList({
    required this.apps,
    required this.onSelected,
  });

  final List<InstalledAppModel> apps;
  final ValueChanged<InstalledAppModel> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Select app',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        Expanded(
          child: apps.isEmpty
              ? Center(
                  child: Text(
                    'No supported apps found on this device.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                )
              : ListView.builder(
                  itemCount: apps.length,
                  itemBuilder: (context, index) {
                    final app = apps[index];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.apps)),
                      title: Text(app.appName),
                      subtitle: Text(app.packageName),
                      onTap: () => onSelected(app),
                    );
                  },
                ),
        ),
      ],
    );
  }
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

