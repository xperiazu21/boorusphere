import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_floating_search_bar/material_floating_search_bar.dart';

import '../../model/server_data.dart';
import '../../provider/api_provider.dart';
import '../../provider/common.dart';
import '../../provider/search_tag.dart';
import '../hooks/floating_searchbar_controller.dart';
import 'search_suggestions.dart';

class HomeBar extends HookWidget {
  void _searchForTag({
    required String value,
    required FloatingSearchBarController controller,
    required SearchTagState searchTagHandler,
    required ApiProvider api,
    required String searchTag,
  }) {
    final query = value.trim();

    // restore title when user cancels search by submitting a blank input
    if (query.isEmpty) {
      if (controller.query != searchTag) {
        controller.query = '$searchTag ';
      }
      return;
    }

    searchTagHandler.setTag(query: query);
    api.fetch(clear: true);
    controller.close();
  }

  @override
  Widget build(BuildContext context) {
    final controller = useFloatingSearchBarController();
    final gridHandler = useProvider(gridProvider.notifier);
    final activeServer = useProvider(activeServerProvider);
    final api = useProvider(apiProvider);
    final searchTag = useProvider(searchTagProvider);
    final searchTagHandler = useProvider(searchTagProvider.notifier);
    final searchHistory = useProvider(searchHistoryProvider);
    final suggestion = useState(<String>[]);
    final suggestionHistory = useState({});
    final homeDrawerSwipeable = useProvider(homeDrawerSwipeableProvider);

    useEffect(() {
      // Populate suggestion history on first build
      searchHistory.mapped.then((it) {
        if (it.isNotEmpty) suggestionHistory.value = it;
      });
    }, [suggestionHistory]);

    return FloatingSearchBar(
      backgroundColor: Theme.of(context).colorScheme.surface,
      implicitDuration: Duration.zero,
      autocorrect: false,
      margins: EdgeInsets.fromLTRB(
          10.5, MediaQuery.of(context).viewPadding.top + 12, 10, 0),
      borderRadius: BorderRadius.circular(8),
      hint: searchTag == ServerData.defaultTag ? 'Search...' : searchTag,
      controller: controller,
      debounceDelay: const Duration(milliseconds: 250),
      transitionCurve: Curves.easeInCirc,
      transition: ExpandingFloatingSearchBarTransition(),
      transitionDuration: const Duration(milliseconds: 250),
      onSubmitted: (value) {
        _searchForTag(
          value: value,
          api: api,
          controller: controller,
          searchTag: searchTag,
          searchTagHandler: searchTagHandler,
        );
      },
      onQueryChanged: (value) async {
        if (activeServer.canSuggestTags) {
          suggestion.value = await api.fetchSuggestion(query: value);
        }
        suggestionHistory.value =
            await searchHistory.composeSuggestion(query: value);
      },
      onFocusChanged: (focused) {
        homeDrawerSwipeable.state = !focused;
      },
      clearQueryOnClose: false,
      actions: [
        FloatingSearchBarAction(
          showIfOpened: false,
          child: CircularButton(
            icon: const Icon(Icons.grid_view),
            onPressed: gridHandler.rotate,
          ),
        ),
        FloatingSearchBarAction.icon(
          icon: const Icon(Icons.rotate_left),
          onTap: () {
            if (controller.query != searchTag) {
              controller.query = '$searchTag ';
            }
          },
          showIfOpened: true,
          showIfClosed: false,
        ),
        FloatingSearchBarAction.searchToClear(
          showIfClosed: false,
        ),
      ],
      builder: (context, transition) {
        return suggestionHistory.value.isEmpty && controller.query.isEmpty
            ? Center(
                child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.history),
                  ),
                  const Text('No search history yet'),
                ],
              ))
            : SearchSuggestionResult(
                controller: controller,
                suggestions: suggestion.value,
                history: suggestionHistory.value,
                onClearHistory: () async {
                  searchHistory.clear();
                  suggestionHistory.value = {};
                },
                onRemoveHistory: (key) async {
                  searchHistory.delete(key);
                  // rebuild history suggestion
                  suggestionHistory.value = await searchHistory
                      .composeSuggestion(query: controller.query);
                },
                onSearchTag: (value) {
                  _searchForTag(
                    value: value,
                    api: api,
                    controller: controller,
                    searchTag: searchTag,
                    searchTagHandler: searchTagHandler,
                  );
                });
      },
    );
  }
}
