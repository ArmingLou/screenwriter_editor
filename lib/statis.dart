class Statis {
  final Map<String, int> characters;
  final Map<String, int> locations;
  final Map<String, int> times;
  final Map<String, int> intexts;
  final Map<String, Map<String, Map<String, int>>>
      locationsTime; // 地点：内外景：时间 ：场次

  Statis({
    required this.characters,
    required this.locations,
    required this.times,
    required this.intexts,
    required this.locationsTime,
  });

  factory Statis.empty() {
    return Statis(
      characters: {},
      locations: {},
      times: {},
      intexts: {},
      locationsTime: {},
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

  void addLocationTimeScenes(
      String name, String intext, String time, int scenes) {
    if (name.isNotEmpty && intext.isNotEmpty && time.isNotEmpty) {
      if (locationsTime.containsKey(name)) {
        if (locationsTime[name]!.containsKey(intext)) {
          if (locationsTime[name]![intext]!.containsKey(time)) {
            locationsTime[name]![intext]![time] =
                locationsTime[name]![intext]![time]! + scenes;
          } else {
            locationsTime[name]![intext]![time] = scenes;
          }
        } else {
          locationsTime[name]![intext] = {time: scenes};
          return;
        }
      } else {
        locationsTime[name] = {
          intext: {time: scenes}
        };
        return;
      }
    }
  }

  bool isEmpty() {
    return (characters.isEmpty ||
            characters.values.every((value) => value == 0)) &&
        locations.isEmpty &&
        times.isEmpty &&
        intexts.isEmpty &&
        locationsTime.isEmpty;
  }
}
