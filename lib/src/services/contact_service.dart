import 'package:flutter_contacts/flutter_contacts.dart';

import '../models/device_contact.dart';

class ContactService {
  Future<bool> requestPermission() async {
    return FlutterContacts.requestPermission(readonly: true);
  }

  Future<List<DeviceContact>> fetchContacts() async {
    final contacts = await FlutterContacts.getContacts(
      withProperties: true,
      withPhoto: false,
    );

    return contacts
        .map(
          (contact) => DeviceContact(
            id: contact.id,
            displayName: contact.displayName,
            phones: contact.phones.map((phone) => phone.number).toList(),
            emails: contact.emails.map((email) => email.address).toList(),
          ),
        )
        .where((contact) => contact.displayName.trim().isNotEmpty)
        .toList()
      ..sort(
        (left, right) => left.displayName.toLowerCase().compareTo(
              right.displayName.toLowerCase(),
            ),
      );
  }
}
