class Recommendation {
  final String name;
  final String category;
  final String? address;
  final String reason;
  final int rank;

  const Recommendation({
    required this.name,
    required this.category,
    this.address,
    required this.reason,
    required this.rank,
  });

  factory Recommendation.fromJson(Map<String, dynamic> json) {
    return Recommendation(
      name: json['name'] as String,
      category: json['category'] as String,
      address: json['address'] as String?,
      reason: json['reason'] as String,
      rank: json['rank'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'category': category,
      'address': address,
      'reason': reason,
      'rank': rank,
    };
  }
}