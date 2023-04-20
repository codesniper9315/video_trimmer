import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/return_code.dart';
import 'package:path/path.dart';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_trimmer/src/entities/hls_result.dart';
import 'package:video_trimmer/src/file_formats.dart';
import 'package:video_trimmer/src/storage_dir.dart';
import 'package:video_trimmer/src/entities/variant_option.dart';

enum TrimmerEvent { initialized }

/// Helps in loading video from file, saving trimmed video to a file
/// and gives video playback controls. Some of the helpful methods
/// are:
/// * [loadVideo()]
/// * [saveTrimmedVideo()]
/// * [videPlaybackControl()]
class Trimmer {
  // final FlutterFFmpeg _flutterFFmpeg = FFmpegKit();

  final StreamController<TrimmerEvent> _controller =
      StreamController<TrimmerEvent>.broadcast();

  VideoPlayerController? _videoPlayerController;

  VideoPlayerController? get videoPlayerController => _videoPlayerController;

  File? currentVideoFile;

  /// Listen to this stream to catch the events
  Stream<TrimmerEvent> get eventStream => _controller.stream;

  /// Loads a video using the path provided.
  ///
  /// Returns the loaded video file.
  Future<void> loadVideo({required File videoFile, bool tsFile = false}) async {
    currentVideoFile = videoFile;
    if (videoFile.existsSync()) {
      if (_videoPlayerController != null) {
        await _videoPlayerController!.dispose();
      }

      // if the input file is ts on iOS
      // initialize directly due to not able to play it on iOS directly
      if (Platform.isIOS && tsFile) {
        _controller.add(TrimmerEvent.initialized);
        return;
      }

      _videoPlayerController = VideoPlayerController.file(currentVideoFile!);
      await _videoPlayerController!.initialize().then((_) {
        _controller.add(TrimmerEvent.initialized);
      });
    }
  }

  Future<String> _createFolderInAppDocDir(
    String folderName,
    StorageDir? storageDir,
  ) async {
    Directory? directory;

    if (storageDir == null) {
      directory = await getApplicationDocumentsDirectory();
    } else {
      switch (storageDir.toString()) {
        case 'temporaryDirectory':
          directory = await getTemporaryDirectory();
          break;

        case 'applicationDocumentsDirectory':
          directory = await getApplicationDocumentsDirectory();
          break;

        case 'externalStorageDirectory':
          directory = await getExternalStorageDirectory();
          break;
      }
    }

    // Directory + folder name
    final Directory directoryFolder =
        Directory('${directory!.path}/$folderName/');

    if (await directoryFolder.exists()) {
      // If folder already exists return path
      debugPrint('Exists');
      return directoryFolder.path;
    } else {
      debugPrint('Creating');
      // If folder does not exists create folder and then return its path
      var directoryNewFolder = await directoryFolder.create(recursive: true);
      return directoryNewFolder.path;
    }
  }

  /// Saves the trimmed video to file system.
  ///
  ///
  /// The required parameters are [startValue], [endValue] & [onSave].
  ///
  /// The optional parameters are [videoFolderName], [videoFileName],
  /// [outputFormat], [fpsGIF], [scaleGIF], [applyVideoEncoding].
  ///
  /// The `@required` parameter [startValue] is for providing a starting point
  /// to the trimmed video. To be specified in `milliseconds`.
  ///
  /// The `@required` parameter [endValue] is for providing an ending point
  /// to the trimmed video. To be specified in `milliseconds`.
  ///
  /// The `@required` parameter [onSave] is a callback Function that helps to
  /// retrieve the output path as the FFmpeg processing is complete. Returns a
  /// `String`.
  ///
  /// The parameter [videoFolderName] is used to
  /// pass a folder name which will be used for creating a new
  /// folder in the selected directory. The default value for
  /// it is `Trimmer`.
  ///
  /// The parameter [videoFileName] is used for giving
  /// a new name to the trimmed video file. By default the
  /// trimmed video is named as `<original_file_name>_trimmed.mp4`.
  ///
  /// The parameter [outputFormat] is used for providing a
  /// file format to the trimmed video. This only accepts value
  /// of [FileFormat] type. By default it is set to `FileFormat.mp4`,
  /// which is for `mp4` files.
  ///
  /// The parameter [storageDir] can be used for providing a storage
  /// location option. It accepts only [StorageDir] values. By default
  /// it is set to [applicationDocumentsDirectory]. Some of the
  /// storage types are:
  ///
  /// * [temporaryDirectory] (Only accessible from inside the app, can be
  /// cleared at anytime)
  ///
  /// * [applicationDocumentsDirectory] (Only accessible from inside the app)
  ///
  /// * [externalStorageDirectory] (Supports only `Android`, accessible externally)
  ///
  /// The parameters [fpsGIF] & [scaleGIF] are used only if the
  /// selected output format is `FileFormat.gif`.
  ///
  /// * [fpsGIF] for providing a FPS value (by default it is set
  /// to `10`)
  ///
  ///
  /// * [scaleGIF] for proving a width to output GIF, the height
  /// is selected by maintaining the aspect ratio automatically (by
  /// default it is set to `480`)
  ///
  ///
  /// * [applyVideoEncoding] for specifying whether to apply video
  /// encoding (by default it is set to `false`).
  ///
  ///
  /// ADVANCED OPTION:
  ///
  /// If you want to give custom `FFmpeg` command, then define
  /// [ffmpegCommand] & [customVideoFormat] strings. The `input path`,
  /// `output path`, `start` and `end` position is already define.
  ///
  /// NOTE: The advanced option does not provide any safety check, so if wrong
  /// video format is passed in [customVideoFormat], then the app may
  /// crash.
  ///
  Future<String?> saveTrimmedVideo({
    required double startValue,
    required double endValue,
    required Function(String? outputPath) onSave,
    bool applyVideoEncoding = false,
    FileFormat? outputFormat,
    String? ffmpegCommand,
    String? customVideoFormat,
    int? fpsGIF,
    int? scaleGIF,
    String? videoFolderName,
    String? videoFileName,
    StorageDir? storageDir,
  }) async {
    final String videoPath = currentVideoFile!.path;
    final String videoName = basename(videoPath).split('.')[0];

    String command;

    // current time (milliseconds)
    String now = DateTime.now().millisecondsSinceEpoch.toString();

    // String _resultString;
    String outputPath;
    String? outputFormatString;

    videoFolderName ??= "Trimmer";

    videoFileName ??= "${videoName}_trimmed_$now";

    videoFileName = videoFileName.replaceAll(' ', '_');

    String path = await _createFolderInAppDocDir(
      videoFolderName,
      storageDir,
    ).whenComplete(
      () => debugPrint("Retrieved Trimmer folder"),
    );

    Duration startPoint = Duration(milliseconds: startValue.toInt());
    Duration endPoint = Duration(milliseconds: endValue.toInt());

    // Checking the start and end point strings
    debugPrint("Start: ${startPoint.toString()} & End: ${endPoint.toString()}");

    debugPrint(path);

    if (outputFormat == null) {
      outputFormat = FileFormat.mp4;
      outputFormatString = outputFormat.toString();
      debugPrint('OUTPUT: $outputFormatString');
    } else {
      outputFormatString = outputFormat.toString();
    }

    String trimLengthCommand =
        ' -ss $startPoint -i "$videoPath" -t ${endPoint - startPoint} -avoid_negative_ts make_zero ';

    if (ffmpegCommand == null) {
      command = '$trimLengthCommand -c:a copy ';

      if (!applyVideoEncoding) {
        command += '-c:v copy ';
      }

      if (outputFormat == FileFormat.gif) {
        fpsGIF ??= 10;
        scaleGIF ??= 480;
        command =
            '$trimLengthCommand -vf "fps=$fpsGIF,scale=$scaleGIF:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" -loop 0 ';
      }
    } else {
      command = '$trimLengthCommand $ffmpegCommand ';
      outputFormatString = customVideoFormat;
    }

    outputPath = '$path$videoFileName$outputFormatString';

    command += '"$outputPath"';

    final session = await FFmpegKit.execute(command);
    final state =
        FFmpegKitConfig.sessionStateToString(await session.getState());
    final returnCode = await session.getReturnCode();

    debugPrint("FFmpeg process exited with state $state and rc $returnCode");

    if (ReturnCode.isSuccess(returnCode)) {
      debugPrint("FFmpeg processing completed successfully.");
      debugPrint('Video successfuly saved');
      // onSave(_outputPath);
      return outputPath;
    } else {
      debugPrint("FFmpeg processing failed.");
      debugPrint('Couldn\'t save the video');
      onSave(null);
    }

    return null;
  }

  Future<String?> convertVideo(
    String formatCommand, [
    FileFormat format = FileFormat.mp4,
  ]) async {
    final String videoPath = currentVideoFile!.path;
    final String videoName = basename(videoPath).split('.')[0];

    String command;

    // current time string
    String now = DateTime.now().millisecondsSinceEpoch.toString();

    // String _resultString;
    String outputPath;
    String? outputFormatString;

    String videoFolderName = "Compress";

    String videoFileName = "${videoName}_compressed_$now";

    videoFileName = videoFileName.replaceAll(' ', '_');

    String path = await _createFolderInAppDocDir(
      videoFolderName,
      null,
    ).whenComplete(
      () => debugPrint("Retrieved Trimmer folder"),
    );

    debugPrint(path);

    FileFormat outputFormat = format;
    outputFormatString = outputFormat.toString();
    debugPrint('OUTPUT: $outputFormatString');

    command = ' -i "$videoPath" $formatCommand ';

    outputPath = '$path$videoFileName$outputFormatString';

    command += '"$outputPath"';

    final session = await FFmpegKit.execute(command);
    final state =
        FFmpegKitConfig.sessionStateToString(await session.getState());
    final returnCode = await session.getReturnCode();

    debugPrint("FFmpeg process exited with state $state and rc $returnCode");

    if (ReturnCode.isSuccess(returnCode)) {
      debugPrint("FFmpeg processing completed successfully.");
      debugPrint('Video successfuly saved');
      // onSave(_outputPath);
      return outputPath;
    } else {
      debugPrint("FFmpeg processing failed.");
      debugPrint('Couldn\'t save the video');
    }

    return null;
  }

  Future<String?> convertM3U8ToMP4(String url) async {
    _controller.add(TrimmerEvent.initialized);

    String command;

    String outputPath;
    String outputFormatString;

    String now = DateTime.now().millisecondsSinceEpoch.toString();
    String videoFileName = 'video_$now';
    String videoFolderName = 'Convert';

    String path = await _createFolderInAppDocDir(
      videoFolderName,
      null,
    ).whenComplete(
      () => debugPrint("Retrieved Converter folder"),
    );

    debugPrint(path);

    FileFormat outputFormat = FileFormat.mp4;
    outputFormatString = outputFormat.toString();
    debugPrint('OUTPUT: $outputFormatString');

    command = '-i "$url" -c copy -bsf:a aac_adtstoasc ';
    outputPath = '$path$videoFileName$outputFormatString';
    command += '"$outputPath"';

    debugPrint('COMMAND: $command');

    final session = await FFmpegKit.execute(command);
    final state =
        FFmpegKitConfig.sessionStateToString(await session.getState());
    final returnCode = await session.getReturnCode();

    debugPrint("FFmpeg process exited with state $state and rc $returnCode");

    if (ReturnCode.isSuccess(returnCode)) {
      debugPrint("FFmpeg processing completed successfully.");
      debugPrint('Video successfuly saved');

      bool isExists = await File(outputPath).exists();
      if (isExists) return outputPath;
    } else {
      debugPrint("FFmpeg processing failed.");
      debugPrint('Couldn\'t save the video');
    }

    return null;
  }

  Future<Map<String, dynamic>?> convertMP4ToM3U8([
    int segmentLength = 5,
  ]) async {
    final String videoPath = currentVideoFile!.path;
    final String videoName = basename(videoPath).split('.')[0];

    String command;

    // current time string
    String now = DateTime.now().millisecondsSinceEpoch.toString();

    // String _resultString;
    String outputPath;
    String? outputFormatString;

    String videoFolderName = "Converter";

    String videoFileName = "${videoName}_converted_$now";

    videoFileName = videoFileName.replaceAll(' ', '_');

    String path = await _createFolderInAppDocDir(
      videoFolderName,
      null,
    ).whenComplete(
      () => debugPrint("Retrieved Converter folder"),
    );

    debugPrint(path);

    FileFormat outputFormat = FileFormat.m3u8;
    outputFormatString = outputFormat.toString();
    debugPrint('OUTPUT: $outputFormatString');

    command =
        ' -i "$videoPath" -f hls -hls_time $segmentLength -hls_list_size 0 -force_key_frames expr:gte(t,n_forced*6) ';
    outputPath = '$path$videoFileName$outputFormatString';
    command += '"$outputPath"';

    final session = await FFmpegKit.execute(command);
    final state =
        FFmpegKitConfig.sessionStateToString(await session.getState());
    final returnCode = await session.getReturnCode();

    debugPrint("FFmpeg process exited with state $state and rc $returnCode");

    if (ReturnCode.isSuccess(returnCode)) {
      debugPrint("FFmpeg processing completed successfully.");
      debugPrint('Video successfuly saved');

      List<String> paths = [];
      bool isExists = await File(outputPath).exists();
      int index = 0;
      while (isExists) {
        debugPrint(outputPath);
        paths.add(outputPath);
        outputPath = '$path$videoFileName${index.toString()}.ts';
        isExists = await File(outputPath).exists();
        index++;
      }
      return {
        'fileName': videoFileName,
        'paths': paths,
      };
    } else {
      debugPrint("FFmpeg processing failed.");
      debugPrint('Couldn\'t save the video');
    }

    return null;
  }

  Future<HLSResult?> convertMP4ToM3U8WithVariants({
    int segmentLength = 5,
    List<VariantOption>? variantSectors,
  }) async {
    variantSectors ??= options;
    variantSectors.sort((a, b) => a.scale.compareTo(b.scale));

    final String videoPath = currentVideoFile!.path;
    double width = _videoPlayerController!.value.size.width;
    double height = _videoPlayerController!.value.size.height;

    String command;

    // String _resultString;
    String outputPath;

    String videoFolderName = "mp4tohlswithvariants";

    String path = await _createFolderInAppDocDir(
      videoFolderName,
      null,
    ).whenComplete(
      () => debugPrint("Retrieved Converter folder"),
    );

    outputPath = '${path}master.m3u8';

    debugPrint(path);

    command = ' -i "$videoPath"';
    for (var _ in variantSectors) {
      command += ' -map 0:v:0 -map 0:a:0';
    }
    command += ' -c:v libx264 -crf 22 -c:a aac -ar 48000';
    for (var i = 0; i < variantSectors.length; i++) {
      var item = variantSectors[i];
      var vW = width * item.scale;
      var vH = height * item.scale;
      command += ' -filter:v:$i scale=w=$vW:h=$vH';
      command += ' -maxrate:v:$i ${item.maxrate} -b:a:0 ${item.bitrate}';
    }
    command += ' -preset slow -hls_list_size 0 -threads 0 -f hls';
    command += ' -hls_playlist_type event -hls_time $segmentLength';
    command += ' -hls_flags independent_segments';
    command += ' -master_pl_name "master.m3u8"';
    command += '"${path}stream_%v.m3u8"';

    final session = await FFmpegKit.execute(command);
    final sessionState = await session.getState();
    final state = FFmpegKitConfig.sessionStateToString(sessionState);
    final returnCode = await session.getReturnCode();

    debugPrint("FFmpeg process exited with state $state and rc $returnCode");

    if (ReturnCode.isSuccess(returnCode)) {
      debugPrint("FFmpeg processing completed successfully.");
      debugPrint('Video successfuly saved');

      var result = HLSResult(masterPath: outputPath, withVariants: true);
      List<HLSResult> variants = [];
      for (var index = 0; index < variantSectors.length; index++) {
        var variantMasterPath = 'stream_$index.m3u8';
        var variant = HLSResult(masterPath: variantMasterPath);
        List<String> paths = [];
        for (var cIndex = 0;; cIndex++) {
          String cPath = '${path}stream_$index$cIndex.ts';
          bool isExists = await File(cPath).exists();
          if (isExists) {
            paths.add(cPath);
          } else {
            break;
          }
        }
        variant.chunkPaths = paths;
        variants.add(variant);
      }
      result.variants = variants;

      return result;
    } else {
      debugPrint("FFmpeg processing failed.");
      debugPrint('Couldn\'t save the video');
    }

    return null;
  }

  /// For getting the video controller state, to know whether the
  /// video is playing or paused currently.
  ///
  /// The two required parameters are [startValue] & [endValue]
  ///
  /// * [startValue] is the current starting point of the video.
  /// * [endValue] is the current ending point of the video.
  ///
  /// Returns a `Future<bool>`, if `true` then video is playing
  /// otherwise paused.
  Future<bool> videPlaybackControl({
    required double startValue,
    required double endValue,
  }) async {
    if (videoPlayerController!.value.isPlaying) {
      await videoPlayerController!.pause();
      return false;
    } else {
      if (videoPlayerController!.value.position.inMilliseconds >=
          endValue.toInt()) {
        await videoPlayerController!
            .seekTo(Duration(milliseconds: startValue.toInt()));
        await videoPlayerController!.play();
        return true;
      } else {
        await videoPlayerController!.play();
        return true;
      }
    }
  }

  void disposeVideo() {
    if (_videoPlayerController != null) {
      _videoPlayerController!.dispose();
    }
  }

  /// Clean up
  void dispose() {
    if (_videoPlayerController != null) {
      _videoPlayerController!.dispose();
    }
    _controller.close();
  }
}
