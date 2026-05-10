class GifResult {
  final String id;
  final String title;
  final String previewUrl;
  final String gifUrl;

  const GifResult({
    required this.id,
    required this.title,
    required this.previewUrl,
    required this.gifUrl,
  });

  factory GifResult.fromJson(Map<String, dynamic> json) => GifResult(
        id: (json['id'] ?? '').toString(),
        title: (json['title'] ?? 'GIF').toString(),
        previewUrl: (json['previewUrl'] ?? '').toString(),
        gifUrl: (json['gifUrl'] ?? '').toString(),
      );
}
