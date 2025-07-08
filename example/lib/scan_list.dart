import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

typedef ItemTapCallback =
    void Function(Map<String, dynamic> item, BuildContext context);

class ScanList extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final IconData icon;
  final ItemTapCallback? onTap;
  final bool disableLoading;

  const ScanList(
    this.items,
    this.icon, {
    this.onTap,
    this.disableLoading = false,
    Key? key,
  }) : super(key: key);

  Widget _buildItem(
    BuildContext _context,
    Map<String, dynamic> item,
    IconData icon, {
    ItemTapCallback? onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: EdgeInsets.all(4.0),
        child: Icon(icon, color: Colors.blueAccent),
      ),
      title: Text(
        item['name'] ?? item['ssid'] ?? '',
        style: TextStyle(color: Theme.of(_context).colorScheme.secondary),
      ),
      trailing: Text(item['rssi']?.toString() ?? ''),
      onTap: () {
        print('tap');
        if (onTap != null) onTap(item, _context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && !disableLoading) {
      return Center(child: SpinKitCircle(color: Colors.blueAccent, size: 50.0));
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) =>
          _buildItem(context, items[index], icon, onTap: onTap),
    );
  }
}
