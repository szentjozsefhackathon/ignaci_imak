import 'package:flutter/material.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';

import '../data/prayer.dart';
import '../data/prayer_group.dart';
import '../data_handlers/data_manager.dart';
import '../routes.dart';

class PrayerSearchDelegate extends SearchDelegate<PrayerSearchResult> {
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
      future: _filter(searchTerm, 50, 15),
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

  final _matchesCache = <String, List<PrayerSearchResult>>{};

  Future<List<PrayerSearchResult>> _filter(
    String query,
    int cutoff,
    int limit,
  ) async {
    final cacheKey = '$cutoff:$limit:$query';
    if (_matchesCache.containsKey(cacheKey)) {
      return _matchesCache[cacheKey]!;
    }
    final groups = await DataManager.instance.prayerGroups.data;
    final result = <PrayerSearchResult>[];
    if (group == null) {
      for (final group in groups) {
        for (final prayer in group.prayers) {
          result.add(PrayerSearchResult._(group, prayer));
        }
      }
    } else {
      for (final prayer in group!.prayers) {
        result.add(PrayerSearchResult._(group!, prayer));
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

class PrayerSearchResult {
  PrayerSearchResult._(this.group, this.prayer);

  final PrayerGroup group;
  final Prayer prayer;

  String get slug => '${group.slug}/${prayer.slug}';
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
