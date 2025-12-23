import 'package:flutter/material.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';

import '../data/database.dart';
import '../routes.dart';

class PrayerSearchDelegate extends SearchDelegate<PrayerWithGroup> {
  PrayerSearchDelegate({this.group});

  final PrayerGroup? group;

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        icon: const Icon(Icons.clear_rounded),
        tooltip: 'Törlés',
        onPressed: () => query = '',
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => null;

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    final searchTerm = query.trim().toLowerCase();
    if (searchTerm.isEmpty) {
      return _buildText(
        'Kezdd el fent beírni a szavakat, ami alapján keressünk címben és leírásban${group == null ? '' : ' "${group!.title}" típusú imák között'}.',
      );
    }
    return FutureBuilder(
      future: _filter(context, searchTerm, 50, 15),
      builder: (context, snapshot) {
        final matches = snapshot.data;
        if (matches == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (matches.isEmpty) {
          return _buildText('Nincs találat erre: "$query"');
        }
        return ListView.builder(
          itemCount: matches.length,
          itemBuilder: (context, index) => ListTile(
            title: Text(matches[index].prayer.title),
            subtitle: group == null ? Text(matches[index].group.title) : null,
            onTap: () => Navigator.pop(context, matches[index]),
          ),
        );
      },
    );
  }

  Widget _buildText(String text) => Padding(
    padding: const EdgeInsets.all(16),
    child: Center(child: Text(text, textAlign: TextAlign.center)),
  );

  final _matchesCache = <String, List<PrayerWithGroup>>{};

  Future<List<PrayerWithGroup>> _filter(
    BuildContext context,
    String query,
    int cutoff,
    int limit,
  ) async {
    final cacheKey = '$cutoff:$limit:$query';
    if (_matchesCache.containsKey(cacheKey)) {
      return _matchesCache[cacheKey]!;
    }
    final db = context.read<Database>();
    // TODO: move filtering logic to dao?
    final result = <PrayerWithGroup>[];
    if (group == null) {
      for (final entry in await db.prayersDao.getPrayersWithGroups()) {
        result.add(entry);
      }
    } else {
      for (final prayer in await db.prayersDao.getPrayersOf(group!)) {
        result.add((group: group!, prayer: prayer));
      }
    }
    if (query.isEmpty) {
      return result;
    }
    final titleMatches = extractTop(
      query: query,
      choices: result,
      limit: limit,
      cutoff: cutoff,
      getter: (item) => item.prayer.title,
    );
    final descriptionMatches = extractTop(
      query: query,
      choices: result,
      limit: limit,
      cutoff: cutoff,
      getter: (item) => item.prayer.description,
    );
    final allMatches = [...titleMatches, ...descriptionMatches];
    final uniqueSlugs = allMatches.map((m) => m.choice.slug).toSet();
    allMatches.retainWhere((m) => uniqueSlugs.remove(m.choice.slug));
    allMatches.sort();
    final matches = allMatches.reversed
        .take(limit)
        .map((item) => item.choice)
        .toList(growable: false);
    _matchesCache[cacheKey] = matches;
    return matches;
  }
}

class PrayerSearchIconButton extends StatelessWidget {
  const PrayerSearchIconButton({super.key, this.group, this.tooltip});

  final PrayerGroup? group;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(Icons.search),
    tooltip: tooltip ?? MaterialLocalizations.of(context).searchFieldLabel,
    onPressed: () async {
      final result = await showSearch(
        context: context,
        delegate: PrayerSearchDelegate(group: group),
      );
      if (result != null && context.mounted) {
        await Navigator.pushNamed(
          context,
          Routes.prayer(result.group, result.prayer),
        );
      }
    },
  );
}
