class VariantOption {
  final double scale;
  final String maxrate;
  final String bitrate;

  VariantOption({
    required this.scale,
    required this.maxrate,
    required this.bitrate,
  });
}

List<VariantOption> options = [
  VariantOption(scale: 0.25, maxrate: '600k', bitrate: '500k'),
  VariantOption(scale: 0.5, maxrate: '1500k', bitrate: '1000k'),
  VariantOption(scale: 0.25, maxrate: '3000k', bitrate: '2000k'),
];
