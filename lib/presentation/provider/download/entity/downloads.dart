import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/download/entity/download_entry.dart';
import 'package:boorusphere/data/repository/download/entity/download_progress.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'downloads.freezed.dart';

@freezed
class Downloads with _$Downloads {
  const factory Downloads({
    @Default([]) List<DownloadEntry> entries,
    @Default({}) Set<DownloadProgress> progresses,
  }) = _Downloads;
  const Downloads._();

  DownloadEntry getEntryByPost(Post post) {
    return entries.lastWhere(
      (it) => it.post == post,
      orElse: () => DownloadEntry.empty,
    );
  }

  DownloadProgress getProgressById(String id) {
    return progresses.firstWhere(
      (it) => it.id == id,
      orElse: () => DownloadProgress.none,
    );
  }

  DownloadProgress getProgressByPost(Post post) {
    final id = getEntryByPost(post).id;
    return progresses.firstWhere(
      (it) => it.id == id,
      orElse: () => DownloadProgress.none,
    );
  }
}
