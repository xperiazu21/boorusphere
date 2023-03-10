import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/cache.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:video_player/video_player.dart';

class VideoPost {
  VideoPost({
    this.downloadProgress = const DownloadProgress('', 0, 0),
    this.controller,
  });

  final DownloadProgress downloadProgress;
  final VideoPlayerController? controller;

  VideoPost copyWith({
    DownloadProgress? downloadProgress,
    VideoPlayerController? controller,
  }) {
    return VideoPost(
      downloadProgress: downloadProgress ?? this.downloadProgress,
      controller: controller ?? this.controller,
    );
  }

  @override
  bool operator ==(covariant VideoPost other) {
    if (identical(this, other)) return true;

    return other.downloadProgress == downloadProgress &&
        other.controller == controller;
  }

  @override
  int get hashCode => downloadProgress.hashCode ^ controller.hashCode;
}

VideoPost useVideoPost(
  WidgetRef ref,
  Post post,
) {
  return use(_VideoPostHook(ref, post));
}

class _VideoPostHook extends Hook<VideoPost> {
  const _VideoPostHook(this.ref, this.post);

  final WidgetRef ref;
  final Post post;

  @override
  _VideoPostState createState() => _VideoPostState();
}

class _VideoPostState extends HookState<VideoPost, _VideoPostHook> {
  _VideoPostState();

  VideoPlayerController? controller;
  VideoPost videoPost = VideoPost();

  WidgetRef get ref => hook.ref;
  Post get post => hook.post;

  void onFileStream(FileResponse event) {
    if (event is DownloadProgress) {
      setState(() {
        videoPost = videoPost.copyWith(downloadProgress: event);
      });
    } else if (event is FileInfo) {
      controller = VideoPlayerController.file(event.file,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true))
        ..setLooping(true);
      final size = event.file.statSync().size;
      final prog = DownloadProgress(event.originalUrl, size, size);

      setState(() {
        videoPost =
            videoPost.copyWith(controller: controller, downloadProgress: prog);
      });
    }
  }

  createController() async {
    final cache = ref.read(cacheManagerProvider);
    final cookieJar = ref.read(cookieJarProvider);
    final cookies = await cookieJar.loadForRequest(post.content.url.toUri());
    final headers =
        ref.read(postHeadersFactoryProvider(post, cookies: cookies));

    cache
        .getFileStream(post.content.url, headers: headers, withProgress: true)
        .listen(onFileStream);
  }

  @override
  void initHook() {
    super.initHook();
    createController();
  }

  @override
  VideoPost build(BuildContext context) => videoPost;

  @override
  void dispose() {
    controller?.pause();
    controller?.dispose();
    super.dispose();
  }

  @override
  String get debugLabel => 'useVideoPost';
}
