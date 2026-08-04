// lib/models/profile.dart

enum Gender { male, female, nonBinary, other, undisclosed }

Gender? _genderFromString(String? value) {
  if (value == null) return null;
  switch (value.toLowerCase()) {
    case 'male':
      return Gender.male;
    case 'female':
      return Gender.female;
    case 'nonbinary':
    case 'non-binary':
    case 'non_binary':
      return Gender.nonBinary;
    case 'other':
      return Gender.other;
    case 'undisclosed':
      return Gender.undisclosed;
    default:
      return null;
  }
}

String? _genderToString(Gender? gender) {
  return gender?.toString().split('.').last;
}

/// Model representing a user profile in MVVM.
class Profile {
  final String name;
  final int? age;
  final String? religion;
  final String? ethnicity;
  final String? language;
  final String? country;
  final Gender? gender;

  const Profile({
    required this.name,
    this.age,
    this.religion,
    this.ethnicity,
    this.language,
    this.country,
    this.gender,
  });

  Profile copyWith({
    String? name,
    int? age,
    String? religion,
    String? ethnicity,
    String? language,
    String? country,
    Gender? gender,
  }) {
    return Profile(
      name: name ?? this.name,
      age: age ?? this.age,
      religion: religion ?? this.religion,
      ethnicity: ethnicity ?? this.ethnicity,
      language: language ?? this.language,
      country: country ?? this.country,
      gender: gender ?? this.gender,
    );
  }

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      name: json['name'] as String? ?? '',
      age: json['age'] is int ? json['age'] as int : (json['age'] != null ? int.tryParse(json['age'].toString()) : null),
      religion: json['religion'] as String?,
      ethnicity: json['ethnicity'] as String?,
      language: json['language'] as String?,
      country: json['country'] as String?,
      gender: _genderFromString(json['gender'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'age': age,
      'religion': religion,
      'ethnicity': ethnicity,
      'language': language,
      'country': country,
      'gender': _genderToString(gender),
    };
  }

  @override
  String toString() {
    return 'Profile(name: $name, age: $age, religion: $religion, ethnicity: $ethnicity, language: $language, country: $country, gender: ${_genderToString(gender)})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Profile &&
        other.name == name &&
        other.age == age &&
        other.religion == religion &&
        other.ethnicity == ethnicity &&
        other.language == language &&
        other.country == country &&
        other.gender == gender;
  }

  @override
  int get hashCode =>
      name.hashCode ^
      (age ?? 0) ^
      (religion?.hashCode ?? 0) ^
      (ethnicity?.hashCode ?? 0) ^
      (language?.hashCode ?? 0) ^
      (country?.hashCode ?? 0) ^
      (gender?.hashCode ?? 0);
}