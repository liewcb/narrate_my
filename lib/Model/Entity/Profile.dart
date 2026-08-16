enum Gender { male, female, nonBinary, other, undisclosed }

class Profile {
  final String id;
  final String name;
  final int? age;
  final String? religion;
  final String? ethnicity;
  final String? language;
  final String? country;
  final Gender? gender;

  const Profile({required this.id, required this.name, this.age, this.religion, this.ethnicity, this.language, this.country, this.gender});
}