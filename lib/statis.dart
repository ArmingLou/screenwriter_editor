class Statis {
  final Map<String, int> characters;
  final Map<String, int> locations;
  final Map<String, int> times;
  final Map<String, int> intexts;

  Statis({
    required this.characters,
    required this.locations,
    required this.times,
    required this.intexts,
  });

  factory Statis.empty() {
    return Statis(
      characters: {},
      locations: {},
      times: {},
      intexts: {},
    );
  }

  void addCharacterChars(String name, int chars) {
    if (name.isNotEmpty) {
      if (characters.containsKey(name)) {
        characters[name] = characters[name]! + chars;
      } else {
        characters[name] = chars;
      }
    }
  }

  void addLocationScenes(String name, int scenes) {
    if (name.isNotEmpty) {
      if (locations.containsKey(name)) {
        locations[name] = locations[name]! + scenes;
      } else {
        locations[name] = scenes;
      }
    }
  }
  void addTimesScenes(String name, int scenes) {
    if (name.isNotEmpty) {
      if (times.containsKey(name)) {
        times[name] = times[name]! + scenes;
      } else {
        times[name] = scenes;
      }
    }
  }
  void addIntextsScenes(String name, int scenes) {
    if (name.isNotEmpty) {
      if (intexts.containsKey(name)) {
        intexts[name] = intexts[name]! + scenes;
      } else {
        intexts[name] = scenes;
      }
    }
  }
}