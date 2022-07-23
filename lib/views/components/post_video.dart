import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../model/booru_post.dart';
import '../../provider/downloader.dart';
import '../../provider/settings/blur_explicit_post.dart';
import '../../provider/settings/video_player.dart';
import '../containers/post.dart';
import '../containers/post_detail.dart';
import '../hooks/refresher.dart';
import 'download_dialog.dart';
import 'post_placeholder_image.dart';

final _videoCacheProvider = Provider((_) => DefaultCacheManager());

final _fetcherProvider =
    Provider.family.autoDispose<CancelableOperation, String>((ref, arg) {
  final cache = ref.read(_videoCacheProvider);
  return CancelableOperation.fromFuture(cache.downloadFile(arg));
});

final _playerControllerProvider = FutureProvider.autoDispose
    .family<VideoPlayerController, String>((ref, arg) async {
  final cache = ref.read(_videoCacheProvider);
  final fromCache = await cache.getFileFromCache(arg);
  if (fromCache != null) {
    return VideoPlayerController.file(fromCache.file);
  }

  final fetcher = ref.read(_fetcherProvider(arg));
  final fromNet = await fetcher.value;
  return VideoPlayerController.file(fromNet.file);
});

class PostVideoDisplay extends HookConsumerWidget {
  const PostVideoDisplay({super.key, required this.booru});

  final BooruPost booru;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fetcher = ref.watch(_fetcherProvider(booru.src));
    final playerController = ref.watch(_playerControllerProvider(booru.src));
    final playerMute = ref.watch(videoPlayerMuteProvider);
    final isFullscreen = ref.watch(postFullscreenProvider.state);
    final blurExplicitPost = ref.watch(blurExplicitPostProvider);
    final cachedController = useState<VideoPlayerController?>(null);
    final showToolbox = useState(true);
    final refresh = useRefresher();
    final isMounted = useIsMounted();

    final autoHideToolbox = useCallback(() {
      Future.delayed(const Duration(seconds: 2), () {
        if (isMounted()) showToolbox.value = false;
      });
    }, [key]);

    final toggleFullscreen = useCallback(() {
      isFullscreen.state = !isFullscreen.state;
      SystemChrome.setPreferredOrientations(isFullscreen.state &&
              booru.width > booru.height
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : []);
      SystemChrome.setEnabledSystemUIMode(
        !isFullscreen.state ? SystemUiMode.edgeToEdge : SystemUiMode.immersive,
      );
      autoHideToolbox();
    }, [key]);

    useEffect(() {
      playerController.whenData((it) {
        cachedController.value = it;
        it.setLooping(true);
        it.initialize().whenComplete(() {
          autoHideToolbox();
          it.addListener(() => refresh());
          it.setVolume(playerMute ? 0 : 1);
          it.play();
        });
      });
    }, [playerController]);

    useEffect(() {
      autoHideToolbox();

      return () {
        cachedController.value?.removeListener(() => refresh());
        cachedController.value?.pause();
        cachedController.value?.dispose();
        fetcher.cancel();
      };
    }, [key]);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        SystemChrome.setEnabledSystemUIMode(isFullscreen.state
            ? SystemUiMode.edgeToEdge
            : SystemUiMode.immersive);
        isFullscreen.state = !isFullscreen.state;
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          ...playerController.maybeWhen(
            data: (controller) => [
              AspectRatio(
                aspectRatio: booru.width / booru.height,
                child: VideoPlayer(controller),
              ),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  showToolbox.value = !showToolbox.value;
                },
                child: showToolbox.value
                    ? _PlayerOverlay(controller: controller)
                    : Container(),
              ),
              if (showToolbox.value)
                _PlayerToolbox(
                  booru: booru,
                  controller: controller,
                  onFullscreenTap: (_) {
                    toggleFullscreen();
                  },
                )
            ],
            orElse: () => [
              AspectRatio(
                aspectRatio: booru.width / booru.height,
                child: PostPlaceholderImage(
                  url: booru.thumbnail,
                  shouldBlur:
                      blurExplicitPost && booru.rating == PostRating.explicit,
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  showToolbox.value = !showToolbox.value;
                },
                child: showToolbox.value ? const _PlayerOverlay() : Container(),
              ),
              if (showToolbox.value)
                _PlayerToolbox(
                  booru: booru,
                  onFullscreenTap: (_) {
                    toggleFullscreen();
                  },
                )
            ],
          ),
        ],
      ),
    );
  }
}

class _PlayerOverlay extends StatelessWidget {
  const _PlayerOverlay({this.controller});

  final VideoPlayerController? controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black38,
      alignment: Alignment.center,
      child: InkWell(
        onTap: () {
          if (controller?.value.isPlaying ?? false) {
            controller?.pause();
          } else {
            controller?.play();
          }
        },
        child: Icon(
          (controller?.value.isPlaying ?? false)
              ? Icons.pause_outlined
              : Icons.play_arrow,
          color: Colors.white,
          size: 64.0,
        ),
      ),
    );
  }
}

class _PlayerToolbox extends HookConsumerWidget {
  const _PlayerToolbox({
    required this.booru,
    this.controller,
    this.onFullscreenTap,
  });

  final BooruPost booru;
  final VideoPlayerController? controller;
  final Function(bool isFullscreen)? onFullscreenTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFullscreen = ref.watch(postFullscreenProvider.state);
    final isMuted = ref.watch(videoPlayerMuteProvider);
    final playerMuteNotifier = ref.watch(videoPlayerMuteProvider.notifier);
    final downloader = ref.watch(downloadProvider);
    final downloadProgress = downloader.getProgressByURL(booru.src);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top,
        16,
        MediaQuery.of(context).padding.bottom + (isFullscreen.state ? 24 : 56),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: downloadProgress.status.isDownloading
                        ? (1 * downloadProgress.progress) / 100
                        : 0,
                  ),
                  IconButton(
                    icon: Icon(downloadProgress.status.isDownloaded
                        ? Icons.download_done
                        : Icons.download),
                    onPressed: () {
                      if (booru.src == booru.displaySrc) {
                        downloader.download(booru);
                      } else {
                        DownloaderDialog.show(context: context, booru: booru);
                      }
                    },
                    color: Colors.white,
                    disabledColor: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
              IconButton(
                onPressed: () async {
                  final mute = await playerMuteNotifier.toggle();
                  controller?.setVolume(mute ? 0 : 1);
                },
                icon: Icon(
                  isMuted ? Icons.volume_mute : Icons.volume_up,
                ),
                color: Colors.white,
              ),
              IconButton(
                icon: const Icon(Icons.info),
                color: Colors.white,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PostDetailsPage(booru: booru),
                    ),
                  );
                },
              ),
              IconButton(
                icon: Icon(
                  isFullscreen.state
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen_outlined,
                ),
                color: Colors.white,
                onPressed: () {
                  onFullscreenTap?.call(isFullscreen.state);
                },
              ),
            ],
          ),
          _PlayerProgress(controller: controller),
        ],
      ),
    );
  }
}

class _PlayerProgress extends StatelessWidget {
  const _PlayerProgress({this.controller});

  final VideoPlayerController? controller;

  @override
  Widget build(BuildContext context) {
    return controller == null || !(controller?.value.isInitialized ?? false)
        ? LinearProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(
              Colors.redAccent.shade700,
            ),
            backgroundColor: Colors.white.withAlpha(20),
          )
        : VideoProgressIndicator(
            controller!,
            colors: VideoProgressColors(
              playedColor: Colors.redAccent.shade700,
              backgroundColor: Colors.white.withAlpha(20),
            ),
            allowScrubbing: true,
          );
  }
}
