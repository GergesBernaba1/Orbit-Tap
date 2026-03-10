import 'package:flutter_test/flutter_test.dart';
import 'package:hidenfiles/src/models/vault_item.dart';

void main() {
  test('vault item serializes type names', () {
    final item = VaultItem(
      id: '1',
      type: VaultItemType.image,
      title: 'secret',
      subtitle: 'secret.jpg',
      createdAt: DateTime(2026, 3, 10),
      metadata: {'key': 'value'},
    );

    expect(item.toJson()['type'], 'image');
  });
}
