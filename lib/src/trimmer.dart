import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_video/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_video/return_code.dart';
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
  Future<void> loadVideo({required File videoFile}) async {
    currentVideoFile = videoFile;
    if (videoFile.existsSync()) {
      if (_videoPlayerController != null) {
        await _videoPlayerController!.dispose();
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
    Directory? _directory;

    if (storageDir == null) {
      _directory = await getApplicationDocumentsDirectory();
    } else {
      switch (storageDir.toString()) {
        case 'temporaryDirectory':
          _directory = await getTemporaryDirectory();
          break;

        case 'applicationDocumentsDirectory':
          _directory = await getApplicationDocumentsDirectory();
          break;

        case 'externalStorageDirectory':
          _directory = await getExternalStorageDirectory();
          break;
      }
    }

    // Directory + folder name
    final Directory _directoryFolder =
        Directory('${_directory!.path}/$folderName/');

    if (await _directoryFolder.exists()) {
      // If folder already exists return path
      debugPrint('Exists');
      return _directoryFolder.path;
    } else {
      debugPrint('Creating');
      // If folder does not exists create folder and then return its path
      var _directoryNewFolder = await _directoryFolder.create(recursive: true);
      return _directoryNewFolder.path;
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
    final String _videoPath = currentVideoFile!.path;
    final String _videoName = basename(_videoPath).split('.')[0];

    String _command;

    // current time (milliseconds)
    String now = DateTime.now().millisecondsSinceEpoch.toString();

    // String _resultString;
    String _outputPath;
    String? _outputFormatString;

    videoFolderName ??= "Trimmer";

    videoFileName ??= "${_videoName}_trimmed_$now";

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
      _outputFormatString = outputFormat.toString();
      debugPrint('OUTPUT: $_outputFormatString');
    } else {
      _outputFormatString = outputFormat.toString();
    }

    String _trimLengthCommand =
        ' -ss $startPoint -i "$_videoPath" -t ${endPoint - startPoint} -avoid_negative_ts make_zero ';

    if (ffmpegCommand == null) {
      _command = '$_trimLengthCommand -c:a copy ';

      if (!applyVideoEncoding) {
        _command += '-c:v copy ';
      }

      if (outputFormat == FileFormat.gif) {
        fpsGIF ??= 10;
        scaleGIF ??= 480;
        _command =
            '$_trimLengthCommand -vf "fps=$fpsGIF,scale=$scaleGIF:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" -loop 0 ';
      }
    } else {
      _command = '$_trimLengthCommand $ffmpegCommand ';
      _outputFormatString = customVideoFormat;
    }

    _outputPath = '$path$videoFileName$_outputFormatString';

    _command += '"$_outputPath"';

    final session = await FFmpegKit.execute(_command);
    final state =
        FFmpegKitConfig.sessionStateToString(await session.getState());
    final returnCode = await session.getReturnCode();

    debugPrint("FFmpeg process exited with state $state and rc $returnCode");

    if (ReturnCode.isSuccess(returnCode)) {
      debugPrint("FFmpeg processing completed successfully.");
      debugPrint('Video successfuly saved');
      // onSave(_outputPath);
      return _outputPath;
    } else {
      debugPrint("FFmpeg processing failed.");
      debugPrint('Couldn\'t save the video');
      onSave(null);
    }

    return null;
  }

  Future<String?> saveCompressedVideo(String formatCommand) async {
    final String _videoPath = currentVideoFile!.path;
    final String _videoName = basename(_videoPath).split('.')[0];

    String _command;

    // current time string
    String now = DateTime.now().millisecondsSinceEpoch.toString();

    // String _resultString;
    String _outputPath;
    String? _outputFormatString;

    String videoFolderName = "Compress";

    String videoFileName = "${_videoName}_compressed_$now";

    videoFileName = videoFileName.replaceAll(' ', '_');

    String path = await _createFolderInAppDocDir(
      videoFolderName,
      null,
    ).whenComplete(
      () => debugPrint("Retrieved Trimmer folder"),
    );

    debugPrint(path);

    FileFormat outputFormat = FileFormat.mp4;
    _outputFormatString = outputFormat.toString();
    debugPrint('OUTPUT: $_outputFormatString');

    _command = ' -i "$_videoPath" $formatCommand ';

    _outputPath = '$path$videoFileName$_outputFormatString';

    _command += '"$_outputPath"';

    final session = await FFmpegKit.execute(_command);
    final state =
        FFmpegKitConfig.sessionStateToString(await session.getState());
    final returnCode = await session.getReturnCode();

    debugPrint("FFmpeg process exited with state $state and rc $returnCode");

    if (ReturnCode.isSuccess(returnCode)) {
      debugPrint("FFmpeg processing completed successfully.");
      debugPrint('Video successfuly saved');
      // onSave(_outputPath);
      return _outputPath;
    } else {
      debugPrint("FFmpeg processing failed.");
      debugPrint('Couldn\'t save the video');
    }

    return null;
  }

  Future<String?> convertM3U8ToMP4(String url) async {
    _controller.add(TrimmerEvent.initialized);

    String _command;

    String _outputPath;
    String _outputFormatString;

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
    _outputFormatString = outputFormat.toString();
    debugPrint('OUTPUT: $_outputFormatString');

    _command = '-i "$url" -c copy -bsf:a aac_adtstoasc ';
    _outputPath = '$path$videoFileName$_outputFormatString';
    _command += '"$_outputPath"';

    debugPrint('COMMAND: $_command');

    final session = await FFmpegKit.execute(_command);
    final state =
        FFmpegKitConfig.sessionStateToString(await session.getState());
    final returnCode = await session.getReturnCode();

    debugPrint("FFmpeg process exited with state $state and rc $returnCode");

    if (ReturnCode.isSuccess(returnCode)) {
      debugPrint("FFmpeg processing completed successfully.");
      debugPrint('Video successfuly saved');

      bool isExists = await File(_outputPath).exists();
      if (isExists) return _outputPath;
    } else {
      debugPrint("FFmpeg processing failed.");
      debugPrint('Couldn\'t save the video');
    }

    return null;
  }

  Future<Map<String, dynamic>?> convertMP4ToM3U8([
    int segmentLength = 5,
  ]) async {
    final String _videoPath = currentVideoFile!.path;
    final String _videoName = basename(_videoPath).split('.')[0];

    String _command;

    // current time string
    String now = DateTime.now().millisecondsSinceEpoch.toString();

    // String _resultString;
    String _outputPath;
    String? _outputFormatString;

    String videoFolderName = "Converter";

    String videoFileName = "${_videoName}_converted_$now";

    videoFileName = videoFileName.replaceAll(' ', '_');

    String path = await _createFolderInAppDocDir(
      videoFolderName,
      null,
    ).whenComplete(
      () => debugPrint("Retrieved Converter folder"),
    );

    debugPrint(path);

    FileFormat outputFormat = FileFormat.m3u8;
    _outputFormatString = outputFormat.toString();
    debugPrint('OUTPUT: $_outputFormatString');

    _command =
        ' -i "$_videoPath" -f hls -hls_time $segmentLength -hls_list_size 0 -force_key_frames expr:gte(t,n_forced*6) ';
    _outputPath = '$path$videoFileName$_outputFormatString';
    _command += '"$_outputPath"';

    final session = await FFmpegKit.execute(_command);
    final state =
        FFmpegKitConfig.sessionStateToString(await session.getState());
    final returnCode = await session.getReturnCode();

    debugPrint("FFmpeg process exited with state $state and rc $returnCode");

    if (ReturnCode.isSuccess(returnCode)) {
      debugPrint("FFmpeg processing completed successfully.");
      debugPrint('Video successfuly saved');

      List<String> paths = [];
      bool isExists = await File(_outputPath).exists();
      int index = 0;
      while (isExists) {
        debugPrint(_outputPath);
        paths.add(_outputPath);
        _outputPath = '$path$videoFileName${index.toString()}.ts';
        isExists = await File(_outputPath).exists();
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

    final String _videoPath = currentVideoFile!.path;
    double width = _videoPlayerController!.value.size.width;
    double height = _videoPlayerController!.value.size.height;

    String _command;

    // String _resultString;
    String _outputPath;

    String videoFolderName = "mp4tohlswithvariants";

    String path = await _createFolderInAppDocDir(
      videoFolderName,
      null,
    ).whenComplete(
      () => debugPrint("Retrieved Converter folder"),
    );

    _outputPath = '${path}master.m3u8';

    debugPrint(path);

    _command = ' -i "$_videoPath"';
    for (var _ in variantSectors) {
      _command += ' -map 0:v:0 -map 0:a:0';
    }
    _command += ' -c:v libx264 -crf 22 -c:a aac -ar 48000';
    for (var i = 0; i < variantSectors.length; i++) {
      var item = variantSectors[i];
      var vW = width * item.scale;
      var vH = height * item.scale;
      _command += ' -filter:v:$i scale=w=$vW:h=$vH';
      _command += ' -maxrate:v:$i ${item.maxrate} -b:a:0 ${item.bitrate}';
    }
    _command += ' -preset slow -hls_list_size 0 -threads 0 -f hls';
    _command += ' -hls_playlist_type event -hls_time $segmentLength';
    _command += ' -hls_flags independent_segments';
    _command += ' -master_pl_name "master.m3u8"';
    _command += '"${path}stream_%v.m3u8"';

    final session = await FFmpegKit.execute(_command);
    final sessionState = await session.getState();
    final state = FFmpegKitConfig.sessionStateToString(sessionState);
    final returnCode = await session.getReturnCode();

    debugPrint("FFmpeg process exited with state $state and rc $returnCode");

    if (ReturnCode.isSuccess(returnCode)) {
      debugPrint("FFmpeg processing completed successfully.");
      debugPrint('Video successfuly saved');

      var result = HLSResult(masterPath: _outputPath, withVariants: true);
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

  /// Clean up
  void dispose() {
    if (_videoPlayerController != null) {
      _videoPlayerController!.dispose();
    }
    _controller.close();
  }
}
