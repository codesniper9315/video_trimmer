class HLSResult {
  final String masterPath;
  final bool withVariants;
  List<String> chunkPaths;
  List<HLSResult> variants;

  HLSResult({
    required this.masterPath,
    this.withVariants = false,
    this.chunkPaths = const [],
    this.variants = const [],
  });
}
