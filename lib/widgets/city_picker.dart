import 'package:flutter/material.dart';

import '../services/location_service.dart';

/// Opens the searchable Philippine city/municipality picker bottom sheet and
/// returns the chosen [PhCity], or null if the sheet was dismissed.
///
/// [selectedLabel] highlights the entry matching the user's current location
/// (a "Name, Province" label as produced by [PhCity.label]).
Future<PhCity?> showCityPicker(BuildContext context,
    {String? selectedLabel, String? title, String? subtitle}) {
  String query = '';
  return showModalBottomSheet<PhCity>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
      // Rank matches so places whose name starts with the query come before
      // ones that merely contain it (e.g. "Taal" before "Kabacan").
      final q = query.toLowerCase();
      final List<PhCity> matches;
      if (q.isEmpty) {
        matches = phCities;
      } else {
        matches = phCities
            .where((c) => c.label.toLowerCase().contains(q))
            .toList()
          ..sort((a, b) {
            final aStarts = a.name.toLowerCase().startsWith(q) ? 0 : 1;
            final bStarts = b.name.toLowerCase().startsWith(q) ? 0 : 1;
            return aStarts != bStarts
                ? aStarts - bStarts
                : a.name.compareTo(b.name);
          });
      }
      return Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text(title ?? 'Your Location',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
              const SizedBox(height: 4),
              Text(
                subtitle ??
                    'Pick your city or municipality — anywhere in the '
                        'Philippines.',
                style: const TextStyle(fontSize: 12, color: Colors.black45),
              ),
              const SizedBox(height: 12),
              Container(
                height: 44,
                decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F2),
                    borderRadius: BorderRadius.circular(22)),
                child: TextField(
                  onChanged: (v) => setSheet(() => query = v.trim()),
                  decoration: const InputDecoration(
                    hintText: 'Search city or municipality…',
                    hintStyle: TextStyle(color: Colors.black38, fontSize: 13),
                    prefixIcon:
                        Icon(Icons.search, color: Colors.black38, size: 20),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: matches.isEmpty
                    ? const Center(
                        child: Text('No matching places',
                            style: TextStyle(
                                color: Colors.black45, fontSize: 13)),
                      )
                    : ListView.builder(
                        itemCount: matches.length,
                        itemBuilder: (_, i) {
                          final city = matches[i];
                          final selected = selectedLabel == city.label;
                          return ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            leading: Icon(
                              selected
                                  ? Icons.location_on
                                  : Icons.location_on_outlined,
                              color: const Color(0xFF6DBF99),
                              size: 22,
                            ),
                            title: Text(city.name,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.normal)),
                            subtitle: Text(city.province,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black45)),
                            trailing: selected
                                ? const Icon(Icons.check_circle,
                                    color: Color(0xFF6DBF99), size: 20)
                                : null,
                            onTap: () => Navigator.pop(ctx, city),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    }),
  );
}
